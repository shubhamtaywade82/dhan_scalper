# frozen_string_literal: true

require "DhanHQ"
require "concurrent"
require_relative "risk_manager"
require_relative "ohlc_fetcher"
require_relative "enhanced_position_tracker"
require_relative "session_reporter"
require_relative "quantity_sizer"
require_relative "option_picker"
require_relative "indicators/holy_grail"
require_relative "balance_providers/paper_wallet"
require_relative "balance_providers/live_balance"
require_relative "brokers/paper_broker"
require_relative "brokers/dhan_broker"
require_relative "tick_cache"
require_relative "services/websocket_manager"
require_relative "services/rate_limiter"
require_relative "services/order_monitor"
require_relative "services/position_reconciler"

module DhanScalper
  class HeadlessApp
    def initialize(config, mode: :paper, logger: nil)
      @config = config
      @mode = mode
      @logger = logger || Logger.new($stdout)
      @stop = false
      @session_start = Time.now

      # Initialize components
      initialize_components

      # Setup signal handlers
      setup_signal_handlers
    end

    def start
      @logger.info "[HEADLESS] Starting DhanScalper Options Buying Bot"
      @logger.info "[MODE] #{@mode.upcase} trading"
      @logger.info "[BALANCE] ₹#{@balance_provider.available_balance.round(0)}"
      @logger.info "[SYMBOLS] #{@config["SYMBOLS"]&.keys&.join(", ") || "None"}"

      # Start background services
      start_websocket_connection
      @risk_manager.start
      @ohlc_fetcher.start
      @order_monitor&.start
      @position_reconciler&.start

      # Main trading loop
      main_trading_loop
    ensure
      cleanup_and_report
    end

    def stop
      @stop = true
    end

    private

    def initialize_components
      # Initialize balance provider
      @balance_provider = if @mode == :paper
                            starting_balance = @config.dig("paper", "starting_balance") || 200_000.0
                            BalanceProviders::PaperWallet.new(starting_balance: starting_balance)
                          else
                            BalanceProviders::LiveBalance.new
                          end

      # Initialize position tracker first
      @position_tracker = EnhancedPositionTracker.new(mode: @mode, logger: @logger)

      # Initialize quantity sizer
      @quantity_sizer = QuantitySizer.new(@config, @balance_provider)

      # Initialize broker
      @broker = if @mode == :paper
                  Brokers::PaperBroker.new(
                    virtual_data_manager: @position_tracker,
                    balance_provider: @balance_provider
                  )
                else
                  Brokers::DhanBroker.new(
                    virtual_data_manager: @position_tracker,
                    balance_provider: @balance_provider
                  )
                end

      # Initialize risk manager
      @risk_manager = RiskManager.new(@config, @position_tracker, @broker, logger: @logger)

      # Initialize OHLC fetcher
      @ohlc_fetcher = OHLCFetcher.new(@config, logger: @logger)

      # Initialize session reporter
      @session_reporter = SessionReporter.new(logger: @logger)

      # Initialize WebSocket manager
      @websocket_manager = Services::WebSocketManager.new(logger: @logger)

      # Initialize order monitor for live trading
      @order_monitor = if @mode == :live
                         Services::OrderMonitor.new(@broker, @position_tracker, logger: @logger)
                       else
                         nil
                       end

      # Initialize position reconciler for live trading
      @position_reconciler = if @mode == :live
                               Services::PositionReconciler.new(@broker, @position_tracker, logger: @logger)
                             else
                               nil
                             end

      # Trading parameters
      @decision_interval = @config.dig("global", "decision_interval") || 10
      @min_signal_strength = @config.dig("global", "min_signal_strength") || 0.6
      @max_positions = @config.dig("global", "max_positions") || 5
      @session_target = @config.dig("global", "min_profit_target") || 1000.0
      @max_day_loss = @config.dig("global", "max_day_loss") || 1500.0
    end

    def setup_signal_handlers
      Signal.trap("INT") { @stop = true }
      Signal.trap("TERM") { @stop = true }
    end

    def start_websocket_connection
      @logger.info "[WEBSOCKET] Connecting to DhanHQ WebSocket..."

      begin
        DhanHQ.configure_with_env
        DhanHQ.logger.level = Logger::WARN
        DhanHQ.logger = Logger.new($stderr)

        # Connect using WebSocketManager
        @websocket_manager.connect

        # Setup tick handler
        @websocket_manager.on_price_update do |price_data|
          TickCache.put(price_data)
          @position_tracker.update_all_positions
        end

        # Subscribe to index instruments
        subscribe_to_instruments

        @logger.info "[WEBSOCKET] Connected successfully"
      rescue StandardError => e
        @logger.error "[WEBSOCKET] Failed to connect: #{e.message}"
        raise
      end
    end

    def subscribe_to_instruments
      @config["SYMBOLS"]&.each_key do |symbol|
        symbol_config = @config["SYMBOLS"][symbol]
        next unless symbol_config["idx_sid"]

        @websocket_manager.subscribe_to_instrument(
          symbol_config["idx_sid"],
          "INDEX"
        )

        @logger.info "[WEBSOCKET] Subscribed to #{symbol} (#{symbol_config["seg_idx"]}:#{symbol_config["idx_sid"]})"
      end
    end

    def main_trading_loop
      last_decision = Time.at(0)
      last_status_update = Time.at(0)
      last_websocket_check = Time.at(0)
      status_interval = 30 # Update status every 30 seconds
      websocket_check_interval = 60 # Check WebSocket every 60 seconds

      @logger.info "[TRADING] Starting main trading loop (interval: #{@decision_interval}s)"

      until @stop
        begin
          # Check session limits
          if should_stop_trading?
            @logger.info "[TRADING] Session limits reached, stopping trading"
            break
          end

          # Check WebSocket connection periodically
          if Time.now - last_websocket_check >= websocket_check_interval
            last_websocket_check = Time.now
            check_websocket_connection
          end

          # Check for new signals
          if Time.now - last_decision >= @decision_interval
            last_decision = Time.now
            check_for_signals
          end

          # Update position tracker
          @position_tracker.update_all_positions

          # Periodic status updates
          if Time.now - last_status_update >= status_interval
            last_status_update = Time.now
            log_trading_status
          end

          sleep(1)
        rescue StandardError => e
          @logger.error "[TRADING] Error in main loop: #{e.message}"
          @logger.error "[TRADING] Backtrace: #{e.backtrace.first(3).join("\n")}"

          # Implement exponential backoff for errors
          error_count ||= 0
          error_count += 1
          sleep_duration = [5 * error_count, 60].min # Max 60 seconds

          @logger.warn "[TRADING] Sleeping for #{sleep_duration}s due to error (count: #{error_count})"
          sleep(sleep_duration)

          # Reset error count after successful operation
          error_count = 0 if error_count > 10
        end
      end
    end

    def check_websocket_connection
      return if @websocket_manager&.connected?

      @logger.warn "[WEBSOCKET] Connection lost, attempting reconnection..."
      begin
        start_websocket_connection
        @logger.info "[WEBSOCKET] Reconnection successful"
      rescue StandardError => e
        @logger.error "[WEBSOCKET] Reconnection failed: #{e.message}"
      end
    end

    def market_open?
      current_time = Time.now
      current_date = current_time.to_date

      # Check if it's a weekend
      return false if current_time.saturday? || current_time.sunday?

      # Market hours: 9:15 AM to 3:30 PM IST
      market_start = Time.new(current_date.year, current_date.month, current_date.day, 9, 15, 0)
      market_end = Time.new(current_date.year, current_date.month, current_date.day, 15, 30, 0)

      # Check if current time is within market hours
      current_time.between?(market_start, market_end)
    end

    def should_stop_trading?
      total_pnl = @position_tracker.get_total_pnl

      # Check max day loss
      if total_pnl <= -@max_day_loss
        @logger.warn "[RISK] Max day loss reached: ₹#{total_pnl.round(2)} (limit: ₹#{@max_day_loss})"
        return true
      end

      # Check session target
      if total_pnl >= @session_target && @position_tracker.get_open_positions.empty?
        @logger.info "[SUCCESS] Session target reached: ₹#{total_pnl.round(2)} (target: ₹#{@session_target})"
        return true
      end

      false
    end

    def check_for_signals
      # Check if market is open before trading
      unless market_open?
        @logger.debug "[SIGNAL] Market is closed, skipping signal check"
        return
      end

      @config["SYMBOLS"]&.each_key do |symbol|
        # Check if we've reached maximum positions
        if @position_tracker.get_open_positions.size >= @max_positions
          @logger.debug "[SIGNAL] Max positions reached (#{@max_positions}), skipping #{symbol}"
          next
        end

        signal = get_holy_grail_signal(symbol)
        next if signal == :none || signal.to_s.include?("weak")

        execute_options_trade(symbol, signal)
      end
    end

    def get_holy_grail_signal(symbol)
      symbol_config = @config["SYMBOLS"][symbol]
      return :none unless symbol_config

      # Get candle data from OHLC fetcher
      candle_data = @ohlc_fetcher.get_candle_data(symbol, "1m")
      return :none unless candle_data

      begin
        holy_grail = Indicators::HolyGrail.new(candles: candle_data.to_hash)
        result = holy_grail.call

        return :none unless result.proceed?

        # Check signal strength
        if result.signal_strength < @min_signal_strength
          @logger.debug "[SIGNAL] #{symbol} signal too weak: #{result.signal_strength.round(2)} < #{@min_signal_strength}"
          return :none
        end

        @logger.info "[SIGNAL] #{symbol} #{result.options_signal} " \
                     "(strength: #{result.signal_strength.round(2)}, " \
                     "bias: #{result.bias}, adx: #{result.adx.round(1)})"

        result.options_signal
      rescue StandardError => e
        @logger.error "[SIGNAL] Error getting signal for #{symbol}: #{e.message}"
        :none
      end
    end

    def execute_options_trade(symbol, signal)
      symbol_config = @config["SYMBOLS"][symbol]
      return unless symbol_config

      begin
        # Get current spot price
        current_spot = get_current_spot_price(symbol)
        return unless current_spot&.positive?

        # Pick ATM or ATM±1 strike
        option_picker = OptionPicker.new(symbol_config, mode: @mode)
        option_data = option_picker.pick_atm_strike(current_spot, signal)
        return unless option_data

        # Calculate position size
        quantity = @quantity_sizer.calculate_quantity(symbol, option_data[:premium])
        return unless quantity.positive?

        # Execute trade
        security_id = signal == :buy_ce ? option_data[:ce_security_id] : option_data[:pe_security_id]
        option_type = signal == :buy_ce ? "CE" : "PE"

        order = @broker.buy_market(
          segment: symbol_config["seg_opt"],
          security_id: security_id,
          quantity: quantity
        )

        if order
          if @mode == :paper
            # Paper trading - add position immediately
            @position_tracker.add_position(
              symbol, option_type, option_data[:strike], option_data[:expiry],
              security_id, quantity, order.avg_price
            )

            @logger.info "[TRADE] #{symbol} #{option_type} #{option_data[:strike]} " \
                         "#{quantity} lots @ ₹#{order.avg_price} (Spot: #{current_spot})"
          else
            # Live trading - add to order monitor
            order_data = {
              symbol: symbol,
              option_type: option_type,
              strike: option_data[:strike],
              expiry: option_data[:expiry],
              security_id: security_id,
              quantity: quantity,
              price: order.avg_price
            }
            @order_monitor.add_pending_order(order.order_id, order_data)

            @logger.info "[TRADE] #{symbol} #{option_type} #{option_data[:strike]} " \
                         "#{quantity} lots @ ₹#{order.avg_price} (Spot: #{current_spot}) " \
                         "(Order ID: #{order.order_id})"
          end
        else
          @logger.error "[TRADE] Failed to place order for #{symbol} #{option_type}"
        end
      rescue StandardError => e
        @logger.error "[TRADE] Error executing trade for #{symbol}: #{e.message}"
      end
    end

    def get_current_spot_price(symbol)
      symbol_config = @config["SYMBOLS"][symbol]
      return nil unless symbol_config

      # Try to get from tick cache first
      price = TickCache.ltp(symbol_config["seg_idx"], symbol_config["idx_sid"])
      return price if price&.positive?

      # Fallback: get from latest candle
      candle_data = @ohlc_fetcher.get_latest_candle(symbol, "1m")
      candle_data&.close
    end

    def log_trading_status
      stats = @position_tracker.get_session_stats
      open_positions = @position_tracker.get_open_positions

      @logger.info "[STATUS] Session P&L: ₹#{stats[:total_pnl].round(2)}, " \
                   "Open Positions: #{open_positions.size}, " \
                   "Trades: #{stats[:total_trades]}, " \
                   "Balance: ₹#{@balance_provider.available_balance.round(0)}"

      return unless open_positions.any?

      open_positions.each do |position|
        @logger.info "[POSITION] #{position[:symbol]} #{position[:option_type]} " \
                     "#{position[:strike]} P&L: ₹#{position[:pnl].round(2)} " \
                     "(#{position[:pnl_percentage].round(1)}%)"
      end
    end

    def cleanup_and_report
      @logger.info "[HEADLESS] Shutting down..."

      # Stop background services
      @risk_manager&.stop
      @ohlc_fetcher&.stop
      @order_monitor&.stop
      @position_reconciler&.stop

      # Disconnect WebSocket
      begin
        @websocket_manager&.disconnect
      rescue StandardError
        nil
      end

      # Generate session report
      begin
        config_summary = {
          mode: @mode,
          symbols: @config["SYMBOLS"]&.keys,
          starting_balance: @balance_provider.total_balance - @position_tracker.get_total_pnl
        }

        @session_reporter.generate_session_report(@position_tracker, @balance_provider, config_summary)
      rescue StandardError => e
        @logger.error "[REPORT] Error generating session report: #{e.message}"
      end

      @logger.info "[HEADLESS] Session complete. Check data/ directory for reports."
    end
  end
end
