# frozen_string_literal: true

require "DhanHQ"
require_relative "base_runner"
require_relative "../services/dhanhq_config"
require_relative "../services/market_feed"
require_relative "../services/websocket_cleanup"

module DhanScalper
  module Runners
    # Live trading runner
    class AppRunner < BaseRunner
      def initialize(config, mode: :live, quiet: false, enhanced: true)
        super

        # Initialize core infrastructure
        @namespace = config.dig("global", "redis_namespace") || "dhan_scalper:v1"
        @csv_master = nil
        @market_feed = nil
        @filtered_instruments = {}
        @universe_sids = Set.new
        @traders = {}
        @ce_map = {}
        @pe_map = {}
      end

      def start
        DhanHQ.configure_with_env

        # Initialize core infrastructure
        initialize_core_infrastructure

        # Ensure global WebSocket cleanup is registered
        DhanScalper::Services::WebSocketCleanup.register_cleanup

        # Try to create WebSocket client with fallback methods
        ws = create_websocket_client
        return unless ws

        setup_websocket_handlers(ws)
        setup_traders(ws)
        display_startup_info

        run_main_loop(ws)
      ensure
        cleanup
        disconnect_websocket
      end

      protected

      def get_total_pnl
        @traders.values.compact.sum(&:session_pnl)
      end

      def no_open_positions?
        @traders.values.compact.none? { |t| instance_open?(t) }
      end

      private

      def initialize_core_infrastructure
        puts "[APP] Initializing core infrastructure..."

        # Using memory-only storage
        puts "[APP] Using memory-only storage"

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

      def setup_websocket_handlers(ws)
        ws.on(:tick) do |t|
          # Normalize the tick data first
          normalized = DhanScalper::Support::TickNormalizer.normalize(t)

          # Store in TickCache (memory-only)

          # Store normalized data in TickCache
          DhanScalper::TickCache.put(normalized) if normalized

          # Mirror latest LTPs into subscriptions view
          if normalized
            rec = { segment: normalized[:segment], security_id: normalized[:security_id], ltp: normalized[:ltp], ts: normalized[:ts], symbol: sym_for(normalized) }
            if normalized[:segment] == "IDX_I"
              @state.upsert_idx_sub(rec)
            else
              @state.upsert_opt_sub(rec)
            end
          end
        end
      end

      def setup_traders(ws)
        @traders = {}
        @ce_map = {}
        @pe_map = {}

        @config["SYMBOLS"]&.each_key do |sym|
          s = sym_cfg(sym)
          if s["idx_sid"].to_s.empty?
            puts "[SKIP] #{sym}: idx_sid not set."
            @traders[sym] = nil
            next
          end

          ws.subscribe_one(segment: s["seg_idx"], security_id: s["idx_sid"])
          spot = wait_for_spot(s)
          picker = OptionPicker.new(s, mode: @mode)
          pick = picker.pick(current_spot: spot)
          @ce_map[sym] = pick[:ce_sid]
          @pe_map[sym] = pick[:pe_sid]

          tr = DhanScalper::Trader.new(
            ws: ws,
            symbol: sym,
            cfg: s,
            picker: OptionPicker.new(s, mode: @mode),
            gl: self,
            state: @state,
            quantity_sizer: @quantity_sizer,
            enhanced: @enhanced,
          )
          tr.subscribe_options(@ce_map[sym], @pe_map[sym])
          puts "[#{sym}] Expiry=#{pick[:expiry]} strikes=#{pick[:strikes].join(", ")}"
          @traders[sym] = tr
        end
      end

      def run_main_loop(_ws)
        last_decision = Time.at(0)
        last_status_update = Time.at(0)
        decision_interval = get_decision_interval
        status_interval = get_status_interval
        risk_loop_interval = get_risk_loop_interval
        charge = get_charge_per_order
        tp_pct = get_tp_pct
        sl_pct = get_sl_pct
        tr_pct = get_trail_pct

        until @stop
          begin
            # Pause/resume by state
            if @state.status == :paused
              sleep 0.2
              next
            end

            # Make trading decisions
            if Time.now - last_decision >= decision_interval
              last_decision = Time.now
              execute_trading_decisions
            end

            # Manage open positions
            manage_open_positions(tp_pct, sl_pct, tr_pct, charge)

            # Update global PnL
            gpn = get_total_pnl
            @state.set_session_pnl(gpn)

            # Periodic status updates
            if @quiet && Time.now - last_status_update >= status_interval
              last_status_update = Time.now
              log_status
            end

            # Check risk limits
            break if check_risk_limits
          rescue StandardError => e
            log_error(e)
          ensure
            sleep risk_loop_interval
          end
        end
      end

      def execute_trading_decisions
        @traders.each do |sym, trader|
          next unless trader

          s = sym_cfg(sym)
          if @enhanced
            use_multi_timeframe = @config.dig("global", "use_multi_timeframe") != false
            secondary_timeframe = @config.dig("global", "secondary_timeframe") || 5
            dir = DhanScalper::TrendEnhanced.new(
              seg_idx: s["seg_idx"],
              sid_idx: s["idx_sid"],
              use_multi_timeframe: use_multi_timeframe,
              secondary_timeframe: secondary_timeframe,
            ).decide
          else
            dir = DhanScalper::Trend.new(seg_idx: s["seg_idx"], sid_idx: s["idx_sid"]).decide
          end
          trader.maybe_enter(dir, @ce_map[sym], @pe_map[sym]) unless @dry
        end
      end

      def manage_open_positions(tp_pct, sl_pct, tr_pct, charge)
        @traders.each_value do |t|
          next unless t # Skip nil traders

          t.manage_open(tp_pct: tp_pct, sl_pct: sl_pct, trail_pct: tr_pct, charge_per_order: charge)
        end
      end

      def create_websocket_client
        # Try multiple methods to create WebSocket client
        methods_to_try = [
          -> { DhanHQ::WS::Client.new(mode: :quote).start },
          -> { DhanHQ::WebSocket::Client.new(mode: :quote).start },
          -> { DhanHQ::WebSocket.new(mode: :quote).start },
          -> { DhanHQ::WS.new(mode: :quote).start },
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
          -> { DhanHQ::WebSocket.disconnect_all! },
        ]

        methods_to_try.each do |method|
          method.call
          return
        rescue StandardError
          next
        end
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
          symbol: "INDEX",
        ).closes.last.to_f
      end

      def sym_for(t)
        # Simple mapping: return "NIFTY"/"BANKNIFTY" for index subs, else "OPT"
        return @config["SYMBOLS"].find { |_, v| v["idx_sid"].to_s == t[:security_id].to_s }&.first if t[:segment] == "IDX_I"

        "OPT"
      end

      def instance_open?(t)
        # Crude: check internal ivar (or add a reader)
        t.instance_variable_get(:@open) != nil
      end

      def filter_and_cache_instruments
        return unless @csv_master

        # Get allowed underlying symbols from config
        allowed_symbols = @config["SYMBOLS"]&.keys || []
        puts "[APP] Filtering instruments for symbols: #{allowed_symbols.join(", ")}"

        # Use optimized symbol-specific loading with caching
        @filtered_instruments = @csv_master.get_instruments_for_symbols(allowed_symbols)

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
              exchange_segment: instrument[:exchange_segment],
            }
          end
        end

        # Cache metadata in memory
        puts "[APP] Cached #{@universe_sids.size} universe SIDs in memory"

        total_instruments = @filtered_instruments.values.sum(&:size)
        puts "[APP] Filtered #{total_instruments} instruments for #{allowed_symbols.size} symbols"
        puts "[APP] Instruments per symbol: #{@filtered_instruments.transform_values(&:size)}"
      end

      def cleanup
        super
        # Stop market feed
        @market_feed&.stop

        # Memory-only storage cleanup complete

        puts "[APP] Cleanup complete"
      end
    end
  end
end
