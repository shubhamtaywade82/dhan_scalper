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

        puts "[APP] WebSocket cleanup registered #{ENV["DISABLE_WEBSOCKET"]}"
        # Check if WebSocket is disabled via environment variable
        if ENV["DISABLE_WEBSOCKET"] == "true"
          puts "[WS] WebSocket disabled via DISABLE_WEBSOCKET=true"
          run_fallback_mode
          return
        end

        # Try to create WebSocket client with retry logic
        ws = create_websocket_with_retry

        if ws
          setup_websocket_handlers(ws)
          setup_traders(ws)
          display_startup_info
          run_main_loop(ws)
        else
          puts "[WS] WebSocket connection failed, falling back to LTP-only mode"
          run_fallback_mode
        end
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

        # Initialize live trading components if in live mode
        if @mode == :live
          initialize_live_trading_components
        end

        puts "[APP] Core infrastructure initialization complete"
      end

      def initialize_live_trading_components
        puts "[APP] Initializing live trading components..."

        # Initialize live balance provider
        @balance_provider = DhanScalper::BalanceProviders::LiveBalance.new(
          logger: @quiet ? Logger.new("/dev/null") : Logger.new($stdout)
        )

        # Initialize live broker
        @broker = DhanScalper::Brokers::DhanBroker.new(
          balance_provider: @balance_provider,
          logger: @quiet ? Logger.new("/dev/null") : Logger.new($stdout)
        )

        # Initialize live position tracker
        @position_tracker = DhanScalper::Services::LivePositionTracker.new(
          broker: @broker,
          balance_provider: @balance_provider,
          logger: @quiet ? Logger.new("/dev/null") : Logger.new($stdout)
        )

        # Initialize live order manager
        @order_manager = DhanScalper::Services::LiveOrderManager.new(
          broker: @broker,
          position_tracker: @position_tracker,
          logger: @quiet ? Logger.new("/dev/null") : Logger.new($stdout)
        )

        puts "[APP] Live trading components initialized"
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

          # Subscribe to WebSocket if available
          if ws
            ws.subscribe_one(segment: s["seg_idx"], security_id: s["idx_sid"])
          end

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

          # Subscribe to options if WebSocket is available
          if ws
            tr.subscribe_options(@ce_map[sym], @pe_map[sym])
          end

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

      def create_websocket_with_retry
        max_retries = 2 # Reduced retries to avoid rate limiting
        retry_delay = 30 # Start with 30 seconds delay

        (1..max_retries).each do |attempt|
          puts "[WS] Connection attempt #{attempt}/#{max_retries}"

          ws = create_websocket_client
          return ws if ws

          if attempt < max_retries
            puts "[WS] Connection failed, retrying in #{retry_delay}s..."
            sleep(retry_delay)
            retry_delay *= 2 # Exponential backoff
          end
        end

        puts "[WS] Failed to establish WebSocket connection after #{max_retries} attempts"
        puts "[WS] This is likely due to rate limiting (429 errors)"
        nil
      end

      def run_fallback_mode
        puts "[FALLBACK] Running in LTP-only mode without WebSocket"
        puts "[FALLBACK] This mode will use REST API for price updates"

        # Initialize traders without WebSocket
        setup_traders(nil)
        display_startup_info

        # Run a simplified main loop that uses LTP fallback
        run_fallback_loop
      end

      def run_fallback_loop
        puts "[FALLBACK] Starting fallback trading loop..."
        puts "[FALLBACK] Using LTP fallback service for price updates"
        last_decision = Time.at(0)
        last_status = Time.at(0)

        loop do
          break if @stop

          current_time = Time.now

          # Execute trading decisions every 60 seconds
          if current_time - last_decision >= 60
            puts "[FALLBACK] Executing trading decisions..."
            execute_trading_decisions
            last_decision = current_time
          end

          # Status update every 30 seconds
          if current_time - last_status >= 30
            puts "[FALLBACK] Status update - checking positions and risk limits"
            check_risk_limits
            last_status = current_time
          end

          sleep(5) # Check every 5 seconds
        end
      rescue Interrupt
        puts "\n[FALLBACK] Shutting down gracefully..."
      rescue StandardError => e
        puts "[FALLBACK] Error in fallback loop: #{e.message}"
        puts "[FALLBACK] Continuing with error handling..."
        retry
      end

      def create_websocket_client
        # Add rate limiting to prevent 429 errors
        @last_ws_attempt ||= Time.at(0)
        min_interval = 5.0 # 5 seconds between connection attempts

        if Time.now - @last_ws_attempt < min_interval
          sleep_time = min_interval - (Time.now - @last_ws_attempt)
          puts "[WS] Rate limiting: waiting #{sleep_time.round(1)}s before next connection attempt"
          sleep(sleep_time)
        end

        @last_ws_attempt = Time.now

        # Try multiple methods to create WebSocket client
        methods_to_try = [
          -> { DhanHQ::WS::Client.new(mode: :quote).start },
          -> { DhanHQ::WebSocket::Client.new(mode: :quote).start },
          -> { DhanHQ::WebSocket.new(mode: :quote).start },
          -> { DhanHQ::WS.new(mode: :quote).start },
        ]

        methods_to_try.each do |method|
          begin
            result = method.call
            if result.respond_to?(:on)
              puts "[WS] Successfully created WebSocket client"
              return result
            end
          rescue StandardError => e
            puts "Warning: Failed to create WebSocket client via method: #{e.message}"
            # If it's a 429 error, wait longer before retrying
            if e.message.include?("429")
              puts "[WS] Rate limited (429), waiting 30s before retry"
              sleep(30)
            end
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
