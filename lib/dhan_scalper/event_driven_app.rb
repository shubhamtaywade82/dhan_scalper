# frozen_string_literal: true

require_relative "config"
require_relative "support/logger"
require_relative "support/event_driven_scheduler"
require_relative "support/atomic_state_manager"
require_relative "balance_providers/atomic_paper_wallet"
require_relative "services/enhanced_position_tracker"
require_relative "brokers/paper_broker"
require_relative "unified_risk_manager"
require_relative "tick_cache"
require_relative "option_picker"
require_relative "quantity_sizer"

module DhanScalper
  class EventDrivenApp
    def initialize(config, mode: :paper, quiet: false, enhanced: true)
      @config = config
      @mode = mode
      @quiet = quiet
      @enhanced = enhanced
      @running = false

      # Initialize logger
      DhanScalper::Support::Logger.setup(level: quiet ? :warn : :info)

      # Initialize components
      initialize_components

      # Initialize event scheduler
      @scheduler = DhanScalper::Support::EventDrivenScheduler.new

      # Initialize state manager
      @state_manager = DhanScalper::Support::AtomicStateManager.new

      logger.info("Event-driven app initialized", component: "EventDrivenApp")
    end

    def start
      return if @running

      @running = true
      logger.info("Starting event-driven application", component: "EventDrivenApp")

      # Start scheduler
      @scheduler.start

      # Start all event-driven components
      start_components

      # Schedule main trading loop
      schedule_trading_loop

      # Schedule risk management
      schedule_risk_management

      # Schedule status reporting
      schedule_status_reporting

      # Schedule market data updates
      schedule_market_data_updates

      logger.info("Event-driven application started", component: "EventDrivenApp")
    end

    def stop
      return unless @running

      logger.info("Stopping event-driven application", component: "EventDrivenApp")

      @running = false

      # Stop scheduler (this will cancel all tasks)
      @scheduler.stop

      # Stop components
      stop_components

      logger.info("Event-driven application stopped", component: "EventDrivenApp")
    end

    def running?
      @running
    end

    private

    def initialize_components
      # Initialize balance provider
      @balance_provider = DhanScalper::BalanceProviders::AtomicPaperWallet.new(
        starting_balance: @config.dig("global", "starting_balance") || 200_000.0,
      )

      # Initialize position tracker
      @position_tracker = DhanScalper::Services::EnhancedPositionTracker.new

      # Initialize broker
      @broker = DhanScalper::Brokers::PaperBroker.new(
        balance_provider: @balance_provider,
        logger: DhanScalper::Support::Logger,
      )

      # Initialize risk manager
      @risk_manager = DhanScalper::UnifiedRiskManager.new(
        @config,
        @position_tracker,
        @broker,
        balance_provider: @balance_provider,
        logger: DhanScalper::Support::Logger,
      )

      # Initialize option picker
      @option_picker = DhanScalper::OptionPicker.new(@config)

      # Initialize quantity sizer
      @quantity_sizer = DhanScalper::QuantitySizer.new(@config, @balance_provider)

      DhanScalper::Support::Logger.info("Components initialized", component: "EventDrivenApp")
    end

    def start_components
      # Start risk manager
      @risk_manager.start

      logger.info("Components started", component: "EventDrivenApp")
    end

    def stop_components
      # Stop risk manager
      @risk_manager&.stop

      logger.info("Components stopped", component: "EventDrivenApp")
    end

    def schedule_trading_loop
      decision_interval = @config.dig("global", "decision_interval_sec") || 60

      @scheduler.schedule_immediate_recurring(
        "trading_loop",
        decision_interval,
      ) do
        execute_trading_cycle
      end

      logger.info(
        "Trading loop scheduled with interval #{decision_interval}s",
        component: "EventDrivenApp",
      )
    end

    def schedule_risk_management
      risk_interval = @config.dig("global", "risk_loop_interval_sec") || 1

      @scheduler.schedule_immediate_recurring(
        "risk_management",
        risk_interval,
      ) do
        execute_risk_management
      end

      logger.info(
        "Risk management scheduled with interval #{risk_interval}s",
        component: "EventDrivenApp",
      )
    end

    def schedule_status_reporting
      report_interval = @config.dig("global", "log_status_every") || 60

      @scheduler.schedule_recurring(
        "status_reporting",
        report_interval,
      ) do
        execute_status_reporting
      end

      logger.info(
        "Status reporting scheduled with interval #{report_interval}s",
        component: "EventDrivenApp",
      )
    end

    def schedule_market_data_updates
      # Schedule market data updates based on configuration
      symbols = @config["symbols"] || ["NIFTY"]

      symbols.each do |symbol|
        @scheduler.schedule_recurring(
          "market_data_#{symbol.downcase}",
          5, # Update every 5 seconds
        ) do
          update_market_data(symbol)
        end
      end

      logger.info(
        "Market data updates scheduled for #{symbols.size} symbols",
        component: "EventDrivenApp",
      )
    end

    def execute_trading_cycle
      return unless @running

      begin
        logger.debug("Executing trading cycle", component: "EventDrivenApp")

        # Get current positions
        positions = @position_tracker.get_positions
        current_position_count = positions.size

        # Check if we can open new positions
        max_positions = @config.dig("global", "max_positions") || 5
        if current_position_count >= max_positions
          logger.debug(
            "Maximum positions reached (#{current_position_count}/#{max_positions})",
            component: "EventDrivenApp",
          )
          return
        end

        # Execute trading logic for each symbol
        symbols = @config["symbols"] || ["NIFTY"]
        symbols.each do |symbol|
          execute_symbol_trading(symbol)
        end
      rescue StandardError => e
        logger.error("Error in trading cycle: #{e.message}", component: "EventDrivenApp")
        logger.error(e.backtrace.first(5).join("\n"), component: "EventDrivenApp")
      end
    end

    def execute_symbol_trading(symbol)
      # This is where the actual trading logic would go
      # For now, just log that we're processing the symbol
      logger.debug("Processing trading for #{symbol}", component: "EventDrivenApp")

      # Example: Check for trading signals, place orders, etc.
      # This would integrate with your existing trading logic
    end

    def execute_risk_management
      return unless @running

      begin
        logger.debug("Executing risk management", component: "EventDrivenApp")

        # Risk management is handled by the UnifiedRiskManager
        # This method can be used for additional risk checks if needed
      rescue StandardError => e
        logger.error("Error in risk management: #{e.message}", component: "EventDrivenApp")
      end
    end

    def execute_status_reporting
      return unless @running

      begin
        # Get current state
        balance_snapshot = @balance_provider.state_snapshot
        positions = @position_tracker.get_positions

        logger.info(
          "Status Report - Available: ₹#{DhanScalper::Support::Money.dec(balance_snapshot[:available])}, " \
          "Used: ₹#{DhanScalper::Support::Money.dec(balance_snapshot[:used])}, " \
          "Total: ₹#{DhanScalper::Support::Money.dec(balance_snapshot[:total])}, " \
          "Positions: #{positions.size}",
          component: "EventDrivenApp",
        )
      rescue StandardError => e
        logger.error("Error in status reporting: #{e.message}", component: "EventDrivenApp")
      end
    end

    def update_market_data(symbol)
      return unless @running

      begin
        logger.debug("Updating market data for #{symbol}", component: "EventDrivenApp")

        # This is where market data updates would be handled
        # For now, just log that we're updating
        # In a real implementation, this would fetch and update tick data
      rescue StandardError => e
        logger.error("Error updating market data for #{symbol}: #{e.message}", component: "EventDrivenApp")
      end
    end

    def logger
      DhanScalper::Support::Logger
    end
  end
end
