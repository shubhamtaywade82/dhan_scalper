# frozen_string_literal: true

require "DhanHQ"
require "ostruct"
require_relative "state"
require_relative "ui/dashboard"
require_relative "ui/simple_logger"
require_relative "virtual_data_manager"
require_relative "quantity_sizer"
require_relative "balance_providers/paper_wallet"
require_relative "balance_providers/live_balance"

module DhanScalper
  class App
    # :live or :paper
    def initialize(cfg, mode: :live, dryrun: false, quiet: false, enhanced: true)
      @cfg = cfg
      @mode = mode
      @dry = dryrun
      @quiet = quiet
      @enhanced = enhanced
      @stop = false
      Signal.trap("INT") { @stop = true }
      Signal.trap("TERM") { @stop = true }
      @state = State.new(symbols: cfg["SYMBOLS"]&.keys || [], session_target: cfg.dig("global", "min_profit_target").to_f,
                         max_day_loss: cfg.dig("global", "max_day_loss").to_f)
      @virtual_data_manager = VirtualDataManager.new

      # Initialize balance provider
      @balance_provider = if @mode == :paper
        starting_balance = cfg.dig("paper", "starting_balance") || 200_000.0
        BalanceProviders::PaperWallet.new(starting_balance: starting_balance)
      else
        BalanceProviders::LiveBalance.new
      end

      # Initialize quantity sizer
      @quantity_sizer = QuantitySizer.new(cfg, @balance_provider)

      # Initialize broker
      @broker = if @mode == :paper
        Brokers::PaperBroker.new(virtual_data_manager: @virtual_data_manager, balance_provider: @balance_provider)
      else
        Brokers::DhanBroker.new(virtual_data_manager: @virtual_data_manager, balance_provider: @balance_provider)
      end
    end

    def start
      DhanHQ.configure_with_env
      DhanHQ.logger.level = (@cfg.dig("global", "log_level") == "DEBUG" ? Logger::DEBUG : Logger::INFO)

      # Try to create WebSocket client with fallback methods
      ws = create_websocket_client
      return unless ws

      ws.on(:tick) do |t|
        DhanScalper::TickCache.put(t)
        # mirror latest LTPs into subscriptions view
        rec = { segment: t[:segment], security_id: t[:security_id], ltp: t[:ltp], ts: t[:ts], symbol: sym_for(t) }
        if t[:segment] == "IDX_I"
          @state.upsert_idx_sub(rec)
        else
          @state.upsert_opt_sub(rec)
        end
      end

      # prepare traders
      traders, ce_map, pe_map = setup_traders(ws)
      puts "[DEBUG] traders class: #{traders.class}, traders: #{traders.inspect}"

      # UI loop (only if not in quiet mode)
      ui = nil
      simple_logger = nil
      unless @quiet
        ui = Thread.new { UI::Dashboard.new(@state, balance_provider: @balance_provider).run }
      else
        simple_logger = UI::SimpleLogger.new(@state, balance_provider: @balance_provider)
      end

      puts "[READY] Symbols: #{@cfg["SYMBOLS"]&.keys&.join(", ") || "None"}"
      puts "[MODE] #{@mode.upcase} trading with balance: ₹#{@balance_provider.available_balance.round(0)}"
      puts "[QUIET] Running in quiet mode - no TTY dashboard" if @quiet
      puts "[CONTROLS] Press Ctrl+C to stop"

      last_decision = Time.at(0)
      last_status_update = Time.at(0)
      decision_interval = @cfg.dig("global", "decision_interval").to_i
      status_interval = 30 # Update status every 30 seconds in quiet mode
      max_dd = @cfg.dig("global", "max_day_loss").to_f
      charge = @cfg.dig("global", "charge_per_order").to_f
      tp_pct = (@cfg.dig("global", "tp_pct") || 0.35).to_f
      sl_pct = (@cfg.dig("global", "sl_pct") || 0.18).to_f
      tr_pct = (@cfg.dig("global", "trail_pct") || 0.12).to_f

      until @stop
        begin
          # pause/resume by state
          if @state.status == :paused
            sleep 0.2
            next
          end

          if Time.now - last_decision >= decision_interval
            last_decision = Time.now
            traders.each do |sym, trader|
              next unless trader

              s = sym_cfg(sym)
              trend_class = @enhanced ? DhanScalper::TrendEnhanced : DhanScalper::Trend
              dir = trend_class.new(seg_idx: s["seg_idx"], sid_idx: s["idx_sid"]).decide
              trader.maybe_enter(dir, ce_map[sym], pe_map[sym]) unless @dry
            end
          end

          traders.each_value do |t|
            next unless t # Skip nil traders
            t.manage_open(tp_pct: tp_pct, sl_pct: sl_pct, trail_pct: tr_pct, charge_per_order: charge)
          end
          gpn = traders.values.compact.sum(&:session_pnl)

          # after each loop, update global PnL into state:
          @state.set_session_pnl(gpn)

          # Periodic status updates in quiet mode
          if @quiet && Time.now - last_status_update >= status_interval
            last_status_update = Time.now
            simple_logger&.update_status(traders)
          end

          if gpn <= -max_dd
            puts "\n[HALT] Max day loss hit (#{gpn.round(0)})."
            break
          end
          if gpn >= @state.session_target && traders.values.compact.none? { |t| instance_open?(t) }
            puts "\n[DONE] Session target reached: #{gpn.round(0)}"
            break
          end
        rescue StandardError => e
          puts "\n[ERR] #{e.class}: #{e.message}"
        ensure
          sleep 0.5
        end
      end
    ensure
      @state.set_status(:stopped)
      begin
        ws&.disconnect!
      rescue StandardError
        nil
      end
      begin
        disconnect_websocket
      rescue StandardError
        nil
      end
      ui&.join(0.2)
    end

    private

    def create_websocket_client
      # Try multiple methods to create WebSocket client
      methods_to_try = [
        -> { DhanHQ::WS::Client.new(mode: :quote).start },
        -> { DhanHQ::WebSocket::Client.new(mode: :quote).start },
        -> { DhanHQ::WebSocket.new(mode: :quote).start },
        -> { DhanHQ::WS.new(mode: :quote).start }
      ]

      methods_to_try.each do |method|
        begin
          result = method.call
          return result if result && result.respond_to?(:on)
        rescue StandardError => e
          puts "Warning: Failed to create WebSocket client via method: #{e.message}"
          next
        end
      end

      puts "Error: Failed to create WebSocket client via all available methods"
      nil
    end

    def disconnect_websocket
      # Try multiple methods to disconnect WebSocket
      methods_to_try = [
        -> { DhanHQ::WS.disconnect_all_local! },
        -> { DhanHQ::WebSocket.disconnect_all_local! },
        -> { DhanHQ::WS.disconnect_all! },
        -> { DhanHQ::WebSocket.disconnect_all! }
      ]

      methods_to_try.each do |method|
        begin
          method.call
          return
        rescue StandardError
          next
        end
      end
    end

    def total_pnl_preview(_trader, net)
      # Optionally add open traders' session_pnl + the candidate net
      # For simplicity return net here; the stopping condition uses realized session sums
      net
    end

    def sym_cfg(sym) = @cfg.fetch("SYMBOLS").fetch(sym)

    def instance_open?(t)
      # crude: check internal ivar (or add a reader)
      t.instance_variable_get(:@open) != nil
    end

    def setup_traders(ws)
      traders = {}
      ce_map = {}
      pe_map = {}

      @cfg["SYMBOLS"]&.each do |sym, _|
        s = sym_cfg(sym)
        if s["idx_sid"].to_s.empty?
          puts "[SKIP] #{sym}: idx_sid not set."
          traders[sym] = nil
          next
        end
        ws.subscribe_one(segment: s["seg_idx"], security_id: s["idx_sid"])
        spot = wait_for_spot(s)
        picker = OptionPicker.new(s, mode: @mode)
        pick = picker.pick(current_spot: spot)
        ce_map[sym] = pick[:ce_sid]
        pe_map[sym] = pick[:pe_sid]

        tr = DhanScalper::Trader.new(
          ws: ws,
          symbol: sym,
          cfg: s,
          picker: OptionPicker.new(s, mode: @mode),
          gl: self,
          state: @state,
          quantity_sizer: @quantity_sizer,
          enhanced: @enhanced
        )
        tr.subscribe_options(ce_map[sym], pe_map[sym])
        puts "[#{sym}] Expiry=#{pick[:expiry]} strikes=#{pick[:strikes].join(", ")}"
        traders[sym] = tr
      end
      [traders, ce_map, pe_map]
    end

    def wait_for_spot(s, timeout: 10)
      t0 = Time.now
      loop do
        l = DhanScalper::TickCache.ltp(s["seg_idx"], s["idx_sid"])&.to_f
        return l if l&.positive?
        break if Time.now - t0 > timeout

        sleep 0.2
      end
      CandleSeries.load_from_dhan_intraday(
        seg: s["seg_idx"],
        sid: s["idx_sid"],
        interval: "1",
        symbol: "INDEX"
      ).closes.last.to_f
    end

    def sym_for(t)
      # simple mapping: return "NIFTY"/"BANKNIFTY" for index subs, else "OPT"
      return @cfg["SYMBOLS"].find { |_, v| v["idx_sid"].to_s == t[:security_id].to_s }&.first if t[:segment] == "IDX_I"

      "OPT"
    end
  end
end
