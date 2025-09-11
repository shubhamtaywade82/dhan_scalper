# frozen_string_literal: true

require "DhanHQ"
require "ostruct"
require_relative "state"
require_relative "virtual_data_manager"
require_relative "quantity_sizer"
require_relative "balance_providers/paper_wallet"
require_relative "balance_providers/live_balance"
require_relative "stores/redis_store"
require_relative "stores/paper_reporter"
require_relative "csv_master"
require_relative "services/dhanhq_config"
require_relative "services/market_feed"

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

      # Initialize core components
      @namespace = cfg.dig("global", "redis_namespace") || "dhan_scalper:v1"
      @redis_store = nil
      @paper_reporter = nil
      @csv_master = nil
      @market_feed = nil

      # Initialize state
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
                  Brokers::PaperBroker.new(virtual_data_manager: @virtual_data_manager,
                                           balance_provider: @balance_provider)
                else
                  Brokers::DhanBroker.new(virtual_data_manager: @virtual_data_manager,
                                          balance_provider: @balance_provider)
                end
    end

    def start
      DhanHQ.configure_with_env
      # Respect logger configured by CLI; do not override level or destination here

      # Initialize core infrastructure
      initialize_core_infrastructure

      # Ensure global WebSocket cleanup is registered
      DhanScalper::Services::WebSocketCleanup.register_cleanup
      # Try to create WebSocket client with fallback methods
      ws = create_websocket_client
      return unless ws

      ws.on(:tick) do |t|
        # Store in Redis if available
        if @redis_store
          tick_data = {
            ltp: t[:ltp]&.to_f,
            ts: t[:ts]&.to_i || Time.now.to_i,
            day_high: t[:day_high]&.to_f,
            day_low: t[:day_low]&.to_f,
            atp: t[:atp]&.to_f,
            vol: t[:vol]&.to_i,
            segment: t[:segment],
            security_id: t[:security_id]
          }
          @redis_store.store_tick(t[:segment], t[:security_id], tick_data)
        end

        # Also store in existing TickCache for backward compatibility
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

      # UI loop (only if not in quiet mode)
      # Simple logging for all modes
      @logger = Logger.new($stdout)

      puts "[READY] Symbols: #{@cfg["SYMBOLS"]&.keys&.join(", ") || "None"}"
      puts "[MODE] #{@mode.upcase} trading with balance: ₹#{@balance_provider.available_balance.round(0)}"
      puts "[QUIET] Running in quiet mode - minimal output" if @quiet
      puts "[CONTROLS] Press Ctrl+C to stop"

      last_decision = Time.at(0)
      last_status_update = Time.at(0)
      decision_interval = (@cfg.dig("global",
                                    "decision_interval_sec") || @cfg.dig("global", "decision_interval") || 60).to_i
      status_interval = (@cfg.dig("global", "log_status_every") || 60).to_i
      risk_loop_interval = (@cfg.dig("global", "risk_loop_interval_sec") || 1).to_f
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
              if @enhanced
                use_multi_timeframe = @cfg.dig("global", "use_multi_timeframe") != false
                secondary_timeframe = @cfg.dig("global", "secondary_timeframe") || 5
                dir = DhanScalper::TrendEnhanced.new(
                  seg_idx: s["seg_idx"],
                  sid_idx: s["idx_sid"],
                  use_multi_timeframe: use_multi_timeframe,
                  secondary_timeframe: secondary_timeframe
                ).decide
              else
                dir = DhanScalper::Trend.new(seg_idx: s["seg_idx"], sid_idx: s["idx_sid"]).decide
              end
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
            # Simple status logging
            puts "[#{Time.now.strftime("%H:%M:%S")}] Status: #{@state.status} | PnL: ₹#{@state.pnl} | Open: #{@state.open.size} | Balance: ₹#{@balance_provider.available_balance.round(0)} (Used: ₹#{@balance_provider.used_balance.round(0)})"
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
          sleep risk_loop_interval
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
    end

    # Preview the global session PnL if a trader were to close with `net` profit/loss.
    # Adds the candidate net to the currently realised session PnL tracked in state.
    def session_pnl_preview(_trader, net)
      @state.pnl + net
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
        result = method.call
        return result if result.respond_to?(:on)
      rescue StandardError => e
        puts "Warning: Failed to create WebSocket client via method: #{e.message}"
        next
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
        method.call
        return
      rescue StandardError
        next
      end
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

      @cfg["SYMBOLS"]&.each_key do |sym|
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

    # Delegate session_target to state
    public

    def session_target
      @state.session_target
    end

    private

    # Initialize core infrastructure components
    def initialize_core_infrastructure
      puts "[APP] Initializing core infrastructure..."

      # Initialize Redis store if Redis is available
      if ENV["TICK_CACHE_BACKEND"] == "redis"
        @redis_store = Stores::RedisStore.new(
          namespace: @namespace,
          logger: Logger.new($stdout)
        )
        @redis_store.connect
        @redis_store.store_config(@cfg)
        puts "[APP] Redis store initialized"
      end

      # Initialize paper reporter
      @paper_reporter = Stores::PaperReporter.new(
        data_dir: "data",
        logger: Logger.new($stdout)
      )
      puts "[APP] Paper reporter initialized"

      # Initialize CSV master and filter instruments
      @csv_master = CsvMaster.new
      filter_and_cache_instruments
      puts "[APP] CSV master initialized and instruments filtered"

      # Initialize market feed
      @market_feed = Services::MarketFeed.new(mode: :quote)
      @market_feed.start([]) # Start with empty instruments
      puts "[APP] Market feed initialized"

      puts "[APP] Core infrastructure initialization complete"
    end

    # Filter and cache instruments for trading
    def filter_and_cache_instruments
      return unless @csv_master

      # Get allowed underlying symbols from config
      allowed_symbols = @cfg["SYMBOLS"]&.keys || []
      puts "[APP] Filtering instruments for symbols: #{allowed_symbols.join(", ")}"

      # Use optimized symbol-specific loading with caching
      @filtered_instruments = @csv_master.get_instruments_for_symbols(allowed_symbols, @redis_store)

      # Filter for OPTIDX and OPTFUT instruments only
      @universe_sids = Set.new

      @filtered_instruments.each do |symbol, instruments|
        @filtered_instruments[symbol] = instruments.select do |instrument|
          next false unless %w[OPTIDX OPTFUT].include?(instrument[:instrument])

          # Add to universe SIDs
          @universe_sids.add(instrument[:security_id])

          # Transform to expected format
          true
        end.map do |instrument|
          {
            security_id: instrument[:security_id],
            underlying_symbol: instrument[:underlying_symbol],
            strike_price: instrument[:strike_price].to_f,
            option_type: instrument[:option_type],
            expiry_date: instrument[:expiry_date],
            lot_size: instrument[:lot_size],
            exchange_segment: instrument[:exchange_segment]
          }
        end
      end

      # Cache in Redis if available
      if @redis_store
        @redis_store.store_universe_sids(@universe_sids.to_a)

        # Cache symbol metadata
        @cfg["SYMBOLS"]&.each do |symbol, symbol_config|
          next unless symbol_config.is_a?(Hash)

          metadata = {
            seg_idx: symbol_config["seg_idx"] || "",
            idx_sid: symbol_config["idx_sid"] || "",
            seg_opt: symbol_config["seg_opt"] || "",
            lot_size: symbol_config["lot_size"] || "",
            strike_step: symbol_config["strike_step"] || ""
          }
          @redis_store.store_symbol_metadata(symbol, metadata)
        end
      end

      total_instruments = @filtered_instruments.values.sum(&:size)
      puts "[APP] Filtered #{total_instruments} instruments for #{allowed_symbols.size} symbols"
      puts "[APP] Instruments per symbol: #{@filtered_instruments.transform_values(&:size)}"
    end

    # Get instruments for a symbol
    def get_instruments_for_symbol(symbol)
      @filtered_instruments[symbol] || []
    end

    # Check if security ID is in universe
    def universe_contains?(security_id)
      return @universe_sids.include?(security_id) unless @redis_store

      @redis_store.universe_contains?(security_id)
    end

    # Get tick data with Redis integration
    def get_tick_data(segment, security_id)
      return nil unless @redis_store

      @redis_store.get_tick(segment, security_id)
    end

    # Get LTP with Redis integration
    def get_ltp(segment, security_id)
      return nil unless @redis_store

      @redis_store.get_ltp(segment, security_id)
    end

    # Cleanup method
    def cleanup
      puts "[APP] Cleaning up..."

      # Stop market feed
      @market_feed&.stop

      # Disconnect Redis store
      @redis_store&.disconnect

      # Disconnect WebSocket
      @ws&.disconnect!

      puts "[APP] Cleanup complete"
    end
  end
end
