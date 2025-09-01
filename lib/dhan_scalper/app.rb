# frozen_string_literal: true

require "DhanHQ"
require "ostruct"
require_relative "state"
require_relative "ui/dashboard"
require_relative "virtual_data_manager"

module DhanScalper
  class App
    # :live or :paper
    def initialize(cfg, mode: :live, dryrun: false)
      @cfg = cfg
      @mode = mode
      @dry = dryrun
      @stop = false
      Signal.trap("INT") { @stop = true }
      Signal.trap("TERM") { @stop = true }
      @state = State.new(symbols: cfg["symbols"], session_target: cfg.dig("global", "min_profit_target").to_f,
                         max_day_loss: cfg.dig("global", "max_day_loss").to_f)
      @virtual_data_manager = VirtualDataManager.new
    end

        def start
      DhanHQ.configure_with_env
      DhanHQ.logger.level = (@cfg.dig("global", "log_level") == "DEBUG" ? Logger::DEBUG : Logger::INFO)

      ws = DhanHQ::WS::Client.new(mode: :quote).start
      ws.on(:tick) do |t|
        Trader::TickCache.put(t)
        # mirror latest LTPs into subscriptions view
        rec = {segment: t[:segment], security_id: t[:security_id], ltp: t[:ltp], ts: t[:ts], symbol: sym_for(t)}
        if t[:segment] == "IDX_I"
          @state.upsert_idx_sub(rec)
        else
          @state.upsert_opt_sub(rec)
        end
      end

      # broker
      broker = (@mode == :paper ?
        DhanScalper::Brokers::PaperBroker.new(virtual_data_manager: @virtual_data_manager) :
        DhanScalper::Brokers::DhanBroker.new(virtual_data_manager: @virtual_data_manager))

      # prepare traders
      ce_map, pe_map, traders = setup_traders(ws)

      # UI loop
      ui = Thread.new { UI::Dashboard.new(@state).run }

      puts "[READY] Symbols: #{@cfg['symbols'].join(", ")}"
      last_decision = Time.at(0)
      decision_interval = @cfg.dig("global","decision_interval").to_i
      max_dd = @cfg.dig("global","max_day_loss").to_f
      charge = @cfg.dig("global","charge_per_order").to_f
      tp_pct = (@cfg.dig("global","tp_pct") || 0.35).to_f
      sl_pct = (@cfg.dig("global","sl_pct") || 0.18).to_f
      tr_pct = (@cfg.dig("global","trail_pct") || 0.12).to_f

      until @stop
        begin
          # pause/resume by state
          if @state.status == :paused
            sleep 0.2
            next
          end

          if Time.now - last_decision >= decision_interval
            last_decision = Time.now
            traders.each do |sym, tr|
              next unless tr
              s = sym_cfg(sym)
              dir = DhanScalper::Trader::Trend.new(seg_idx: s["seg_idx"], sid_idx: s["idx_sid"]).decide
              tr.maybe_enter(dir, ce_map[sym], pe_map[sym]) unless @dry
            end
          end

          traders.each_value { |t| t&.manage_open(tp_pct: tp_pct, sl_pct: sl_pct, trail_pct: tr_pct, charge_per_order: charge) }
          gpn = traders.values.compact.sum(&:session_pnl)

          # after each loop, update global PnL into state:
          @state.set_session_pnl(gpn)

          if gpn <= -max_dd
            puts "\n[HALT] Max day loss hit (#{gpn.round(0)})."
            break
          end
          if gpn >= @state.session_target && traders.values.none?{|t| instance_open?(t)}
            puts "\n[DONE] Session target reached: #{gpn.round(0)}"
            break
          end
        rescue => e
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
        DhanHQ::WS.disconnect_all_local!
      rescue StandardError
        nil
      end
      ui&.join(0.2)
    end

    private

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
      ce_map, pe_map = {}, {}

      @cfg["symbols"].each do |sym|
        s = sym_cfg(sym)
        if s["idx_sid"].to_s.empty?
          puts "[SKIP] #{sym}: idx_sid not set."
          traders[sym]=nil; next
        end
        ws.subscribe_one(segment: s["seg_idx"], security_id: s["idx_sid"])
        spot = wait_for_spot(s)
        picker = OptionPicker.new(s)
        pick = picker.pick(current_spot: spot)
        ce_map[sym] = pick[:ce_sid]; pe_map[sym] = pick[:pe_sid]

        tr = Trader.new(ws: ws, symbol: sym, cfg: s, picker: picker, gl: self, state: @state)
        tr.subscribe_options(ce_map[sym], pe_map[sym])
        puts "[#{sym}] Expiry=#{pick[:expiry]} strikes=#{pick[:strikes].join(", ")}"
        traders[sym]=tr
      end
      [traders, ce_map, pe_map]
    end

    def wait_for_spot(s, timeout: 10)
      t0 = Time.now
      loop do
        l = Trader::TickCache.ltp(s["seg_idx"], s["idx_sid"])&.to_f
        return l if l && l.positive?
        break if Time.now - t0 > timeout
        sleep 0.2
      end
      Bars.c1(seg: s["seg_idx"], sid: s["idx_sid"]).last.to_f
    end

    def sym_for(t)
      # simple mapping: return "NIFTY"/"BANKNIFTY" for index subs, else "OPT"
      return @cfg["SYMBOLS"].find { |_, v| v["idx_sid"].to_s == t[:security_id].to_s }&.first if t[:segment] == "IDX_I"
      "OPT"
    end
  end
end
