# frozen_string_literal: true

require_relative "config"
require_relative "cache/redis_adapter"
require_relative "cache/memory_adapter"
require_relative "analyzers/position_analyzer"
require_relative "risk/no_loss_trend_rider"
require_relative "managers/entry_manager"
require_relative "managers/exit_manager"
require_relative "guards/session_guard"
require_relative "notifications/telegram_notifier"
require_relative "services/websocket_manager"
require_relative "services/paper_position_tracker"
require_relative "services/trend_filter"
require_relative "services/sizing_calculator"
require_relative "services/order_manager"

module DhanScalper
  # Enhanced application implementing the full specification
  class EnhancedApp
    attr_reader :config, :cache, :logger, :notifier, :session_guard, :entry_manager, :exit_manager, :position_tracker,
                :websocket_manager

    def initialize(config_path: "config/enhanced_scalper.yml")
      @config = Config.load(path: config_path)
      @logger = Logger.new($stdout)
      @running = false

      initialize_components
    end

    def start
      @logger.info "[ENHANCED] Starting DhanScalper Enhanced Mode"
      @logger.info "[ENHANCED] Mode: #{@config["mode"]}"
      @logger.info "[ENHANCED] Place Orders: #{@config["place_order"]}"

      @running = true

      begin
        # Start WebSocket connection
        start_websocket

        # Main trading loop
        main_loop
      rescue Interrupt
        @logger.info "[ENHANCED] Received interrupt signal"
      rescue StandardError => e
        @logger.error "[ENHANCED] Fatal error: #{e.message}"
        @logger.error e.backtrace.join("\n")
      ensure
        cleanup
      end
    end

    def stop
      @running = false
      @logger.info "[ENHANCED] Stopping application"
    end

    private

    def initialize_components
      # Initialize cache
      @cache = initialize_cache

      # Initialize notifier
      @notifier = TelegramNotifier.new(
        enabled: @config.dig("notifications", "telegram_enabled"),
        logger: @logger
      )

      # Initialize position tracker
      @position_tracker = Services::PaperPositionTracker.new(
        websocket_manager: nil, # Will be set later
        logger: @logger
      )

      # Initialize session guard
      @session_guard = Guards::SessionGuard.new(
        config: @config,
        position_tracker: @position_tracker,
        cache: @cache,
        logger: @logger
      )

      # Initialize position analyzer
      position_analyzer = Analyzers::PositionAnalyzer.new(
        cache: @cache,
        tick_cache: TickCache
      )

      # Initialize No-Loss Trend Rider
      no_loss_trend_rider = Risk::NoLossTrendRider.new(
        config: @config,
        position_analyzer: position_analyzer,
        cache: @cache
      )

      # Initialize services
      series_loader = lambda do |seg:, sid:, interval:|
        CandleSeries.load_from_dhan_intraday(seg: seg, sid: sid, interval: interval, symbol: "INDEX")
      end

      trend_filter = Services::TrendFilter.new(
        logger: @logger,
        cache: @cache,
        config: @config,
        series_loader: series_loader,
        streak_window_minutes: @config.dig("trend", "streak_window_minutes") || 3
      )

      sizing_calculator = Services::SizingCalculator.new(
        config: @config,
        logger: @logger
      )

      # Build brokers
      paper_broker = Brokers::PaperBroker.new(
        virtual_data_manager: nil,
        balance_provider: BalanceProviders::PaperWallet.new(starting_balance: (@config.dig("global", "paper_wallet_rupees") || 200_000).to_f),
        logger: @logger
      )

      live_broker = Brokers::DhanBroker.new(logger: @logger) # assumes credentials via env/config

      order_manager = Services::OrderManager.new(
        config: @config,
        cache: @cache,
        broker_paper: paper_broker,
        broker_live: live_broker,
        logger: @logger
      )

      # Initialize managers
      @entry_manager = Managers::EntryManager.new(
        config: @config,
        trend_filter: trend_filter,
        sizing_calculator: sizing_calculator,
        order_manager: order_manager,
        position_tracker: @position_tracker,
        csv_master: CsvMaster.new,
        logger: @logger
      )

      @exit_manager = Managers::ExitManager.new(
        config: @config,
        no_loss_trend_rider: no_loss_trend_rider,
        order_manager: order_manager,
        position_tracker: @position_tracker,
        logger: @logger
      )

      # Initialize WebSocket manager
      @websocket_manager = Services::WebSocketManager.new(logger: @logger)
      @position_tracker.instance_variable_set(:@websocket_manager, @websocket_manager)
    end

    def initialize_cache
      cache_type = @config.dig("market_data", "cache_type") || "memory"

      case cache_type
      when "redis"
        RedisAdapter.new(
          url: @config.dig("market_data", "redis_url"),
          logger: @logger
        )
      else
        MemoryAdapter.new(logger: @logger)
      end
    end

    def start_websocket
      @logger.info "[ENHANCED] Starting WebSocket connection"

      @websocket_manager.connect

      # Subscribe to underlying instruments
      @config["SYMBOLS"]&.each_key do |symbol|
        symbol_config = @config.dig("SYMBOLS", symbol)
        next unless symbol_config

        @websocket_manager.subscribe_to_instrument(
          symbol_config["idx_sid"],
          "INDEX"
        )
      end

      # Setup price update handler
      @websocket_manager.on_price_update do |price_data|
        handle_price_update(price_data)
      end
    end

    def main_loop
      @logger.info "[ENHANCED] Starting main trading loop"

      last_heartbeat = Time.now
      heartbeat_interval = @config.dig("market_data", "heartbeat_interval") || 60

      while @running
        begin
          # Check session guard
          session_status = @session_guard.call

          case session_status
          when :panic_switch
            @logger.warn "[ENHANCED] Panic switch activated - exiting all positions"
            @session_guard.force_exit_all
            break
          when :day_loss_limit
            @logger.warn "[ENHANCED] Day loss limit breached - exiting all positions"
            @session_guard.force_exit_all
            break
          when :market_closed
            @logger.info "[ENHANCED] Market closed - waiting"
            sleep(60)
            next
          when :feed_stale
            @logger.warn "[ENHANCED] Feed stale - skipping this cycle"
            sleep(10)
            next
          end

          # Process entries
          process_entries

          # Process exits
          process_exits

          # Send heartbeat
          if Time.now - last_heartbeat >= heartbeat_interval
            send_heartbeat
            last_heartbeat = Time.now
          end

          # Sleep for decision interval
          decision_interval = @config.dig("global", "decision_interval") || 10
          sleep(decision_interval)
        rescue StandardError => e
          @logger.error "[ENHANCED] Error in main loop: #{e.message}"
          @notifier.notify_error(e.message, "main_loop") if @notifier
          sleep(5)
        end
      end
    end

    def process_entries
      @config["SYMBOLS"]&.each_key do |symbol|
        # Get current spot price
        spot_price = get_spot_price(symbol)
        next unless spot_price&.positive?

        # Try to enter position
        result = @entry_manager.call(symbol, spot_price)

        case result
        when :success
          @logger.info "[ENHANCED] Entry successful for #{symbol}"
        when :market_closed, :max_positions_reached, :insufficient_budget
          # These are expected conditions, not errors
        else
          @logger.debug "[ENHANCED] Entry skipped for #{symbol}: #{result}"
        end
      rescue StandardError => e
        @logger.error "[ENHANCED] Error processing entry for #{symbol}: #{e.message}"
      end
    end

    def process_exits
      results = @exit_manager.call

      results.each do |result|
        case result
        when :exit_placed
          @logger.info "[ENHANCED] Exit order placed"
        when :stop_adjusted
          @logger.info "[ENHANCED] Stop loss adjusted"
        when :exit_failed
          @logger.error "[ENHANCED] Exit order failed"
        end
      end
    end

    def get_spot_price(symbol)
      symbol_config = @config.dig("SYMBOLS", symbol)
      return nil unless symbol_config

      TickCache.ltp(symbol_config["seg_idx"], symbol_config["idx_sid"])
    end

    def handle_price_update(price_data)
      # Update tick cache
      tick_data = {
        segment: price_data[:segment],
        security_id: price_data[:instrument_id],
        ltp: price_data[:last_price],
        open: price_data[:open],
        high: price_data[:high],
        low: price_data[:low],
        close: price_data[:close],
        volume: price_data[:volume],
        ts: price_data[:timestamp]
      }

      TickCache.put(tick_data)

      # Update cache heartbeat
      @cache.set_heartbeat
    end

    def send_heartbeat
      equity = @position_tracker.get_total_pnl + 200_000 # Starting balance
      positions_count = @position_tracker.get_open_positions.size
      last_feed = @cache.get_heartbeat
      last_feed_time = last_feed ? Time.parse(last_feed) : Time.now

      @notifier.notify_heartbeat(equity, positions_count, last_feed_time) if @notifier

      @logger.info "[ENHANCED] Heartbeat - Equity: ₹#{equity.round(0)}, Positions: #{positions_count}"
    end

    def cleanup
      @logger.info "[ENHANCED] Cleaning up..."

      @websocket_manager&.disconnect
      @cache&.disconnect

      @logger.info "[ENHANCED] Cleanup complete"
    end
  end
end
