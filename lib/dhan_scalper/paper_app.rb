# frozen_string_literal: true

require "logger"
require_relative "state"
require_relative "brokers/base"
require_relative "brokers/paper_broker"
require_relative "balance_providers/paper_wallet"
require_relative "quantity_sizer"
require_relative "trend_enhanced"
require_relative "option_picker"
require_relative "services/websocket_manager"
require_relative "services/paper_position_tracker"
require_relative "ui/simple_logger"

module DhanScalper
  class PaperApp
    def initialize(cfg, quiet: false, enhanced: true, timeout_minutes: nil)
      @cfg = cfg
      @quiet = quiet
      @enhanced = enhanced
      @timeout_minutes = timeout_minutes
      @stop = false
      @start_time = Time.now
      Signal.trap("INT") { @stop = true }
      Signal.trap("TERM") { @stop = true }

      @state = State.new(
        symbols: cfg["SYMBOLS"]&.keys || [],
        session_target: cfg.dig("global", "min_profit_target").to_f,
        max_day_loss: cfg.dig("global", "max_day_loss").to_f
      )

      @virtual_data_manager = VirtualDataManager.new

      # Initialize balance provider
      starting_balance = cfg.dig("paper", "starting_balance") || 200_000.0
      @balance_provider = BalanceProviders::PaperWallet.new(starting_balance: starting_balance)

      # Initialize quantity sizer
      @quantity_sizer = QuantitySizer.new(cfg, @balance_provider)

      # Initialize broker
      @broker = Brokers::PaperBroker.new(
        virtual_data_manager: @virtual_data_manager,
        balance_provider: @balance_provider
      )

      # Initialize WebSocket manager
      @websocket_manager = Services::WebSocketManager.new(logger: @logger)

      # Initialize position tracker
      @position_tracker = Services::PaperPositionTracker.new(
        websocket_manager: @websocket_manager,
        logger: @logger
      )

      # Initialize logger
      @logger = Logger.new($stdout)
      @logger.level = quiet ? Logger::WARN : Logger::INFO

      # Cache for trend objects and option pickers
      @cached_trends = {}
      @cached_pickers = {}
    end

    def start
      DhanHQ.configure_with_env
      DhanHQ.logger.level = Logger::WARN

      puts "[PAPER] Starting paper trading mode"
      puts "[PAPER] WebSocket connection will be established"
      puts "[PAPER] Positions will be tracked in real-time"
      puts "[PAPER] No real money will be used"
      puts "[TIMEOUT] Auto-exit after #{@timeout_minutes} minutes" if @timeout_minutes

      # Initialize simple logger for quiet mode
      simple_logger = UI::SimpleLogger.new(@state, balance_provider: @balance_provider) if @quiet

      puts "[READY] Symbols: #{@cfg["SYMBOLS"]&.keys&.join(", ") || "None"}"
      puts "[MODE] PAPER with balance: ₹#{@balance_provider.available_balance.round(0)}"
      puts "[QUIET] Running in quiet mode - minimal output" if @quiet
      puts "[CONTROLS] Press Ctrl+C to stop"

      begin
        # Connect to WebSocket
        @websocket_manager.connect

        # Start tracking underlying instruments
        start_tracking_underlyings

        # Main trading loop
        last_decision = Time.at(0)
        last_status_update = Time.at(0)
        decision_interval = @cfg.dig("global", "decision_interval").to_i
        status_interval = 30

        until @stop
          begin
            # Check timeout
            if @timeout_minutes && (Time.now - @start_time) >= (@timeout_minutes * 60)
              puts "[TIMEOUT] #{@timeout_minutes} minutes elapsed. Auto-exiting..."
              @stop = true
              break
            end

            # Pause/resume by state
            if @state.status == :paused
              sleep 0.2
              next
            end

            # Make trading decisions
            if Time.now - last_decision >= decision_interval
              last_decision = Time.now
              analyze_and_trade
            end

            # Risk management
            check_risk_limits

            # Periodic status updates
            if @quiet && Time.now - last_status_update >= status_interval
              last_status_update = Time.now
              simple_logger&.update_status({})
            end

            # Show position summary periodically
            if Time.now - last_status_update >= 60 # Every minute
              show_position_summary
              if @timeout_minutes
                elapsed = (Time.now - @start_time) / 60
                remaining = @timeout_minutes - elapsed
                puts "[TIMEOUT] #{remaining.round(1)} minutes remaining" if remaining > 0
              end
              last_status_update = Time.now
            end

          rescue StandardError => e
            puts "\n[ERR] #{e.class}: #{e.message}"
            puts e.backtrace.first(5).join("\n") if @cfg.dig("global", "log_level") == "DEBUG"
          ensure
            sleep 0.5
          end
        end

      ensure
        @state.set_status(:stopped)
        @websocket_manager.disconnect
        puts "\n[PAPER] Trading stopped"
        show_final_summary
      end
    end

    private

    def start_tracking_underlyings
      @cfg["SYMBOLS"]&.each_key do |sym|
        next unless sym

        s = sym_cfg(sym)
        next if s["idx_sid"].to_s.empty?

        puts "[PAPER] Starting to track underlying: #{sym}"

        # Track the underlying index
        success = @position_tracker.track_underlying(sym, s["idx_sid"])

        if success
          puts "[PAPER] Now tracking #{sym} (#{s["idx_sid"]})"
        else
          puts "[PAPER] Failed to track #{sym}"
        end
      end
    end

    def analyze_and_trade
      @cfg["SYMBOLS"]&.each_key do |sym|
        next unless sym

        s = sym_cfg(sym)
        next if s["idx_sid"].to_s.empty?

        begin
          # Get current spot price from WebSocket
          spot_price = @position_tracker.get_underlying_price(sym)

          if spot_price.nil?
            puts "[#{sym}] No price data available yet, skipping..."
            next
          end

          puts "\n[#{sym}] Analyzing signals at spot: #{spot_price}"

          # Get trend direction
          trend = get_cached_trend(sym, s)
          direction = trend.decide

          puts "[#{sym}] Signal: #{direction}"

          # Execute trades based on signals
          execute_trade(sym, direction, spot_price, s) if direction != :none

        rescue StandardError => e
          puts "[#{sym}] Error in analysis: #{e.message}"
          puts e.backtrace.first(3).join("\n") if @cfg.dig("global", "log_level") == "DEBUG"
        end
      end
    end

    def execute_trade(symbol, direction, spot_price, symbol_config)
      return if direction == :none

      # Get option picker
      picker = get_cached_picker(symbol, symbol_config)
      pick = picker.pick(current_spot: spot_price)

      return unless pick[:ce_sid] && pick[:pe_sid]

      # Calculate the actual strike price (ATM)
      strike_step = symbol_config["strike_step"] || 50
      actual_strike = picker.nearest_strike(spot_price, strike_step)

      # Determine which option to trade
      option_sid = case direction
                   when :bullish, :long_ce
                     pick[:ce_sid][actual_strike]
                   when :bearish, :long_pe
                     pick[:pe_sid][actual_strike]
                   else
                     return
                   end

      return unless option_sid

      option_type = case direction
                    when :bullish, :long_ce
                      "CE"
                    when :bearish, :long_pe
                      "PE"
                    end

      # Calculate position size
      option_price = 50.0 # Mock option price for now
      lots = @quantity_sizer.calculate_lots(symbol, option_price, side: "BUY")
      quantity = @quantity_sizer.calculate_quantity(symbol, option_price, side: "BUY")

      puts "[#{symbol}] Executing #{direction} trade: #{option_type} #{quantity} lots at ₹#{option_price} (Strike: #{actual_strike})"

      # Place paper order
      order_result = @broker.place_order(
        symbol: symbol,
        instrument_id: option_sid,
        side: "BUY",
        quantity: quantity,
        price: option_price,
        order_type: "MARKET"
      )

      if order_result[:success]
        puts "[#{symbol}] Order placed successfully: #{order_result[:order_id]}"

        # Add position to tracker
        position_key = "#{symbol}_#{option_type}_#{actual_strike}_#{Date.today}"
        @position_tracker.add_position(
          symbol, option_type, actual_strike, Date.today,
          option_sid, quantity, option_price
        )

        puts "[#{symbol}] Position added to tracker: #{position_key}"
      else
        puts "[#{symbol}] Order failed: #{order_result[:error]}"
      end
    end

    def check_risk_limits
      # Check daily loss limit
      total_pnl = @position_tracker.get_total_pnl
      max_loss = @cfg.dig("global", "max_day_loss").to_f

      if total_pnl < -max_loss
        puts "[RISK] Daily loss limit exceeded: ₹#{total_pnl} (limit: ₹#{max_loss})"
        puts "[RISK] Stopping trading for today"
        @stop = true
      end

      # Check position limits
      max_positions = @cfg.dig("global", "max_positions").to_i
      if max_positions > 0 && @position_tracker.positions.size >= max_positions
        puts "[RISK] Maximum positions reached: #{@position_tracker.positions.size}"
        puts "[RISK] No new positions will be opened"
      end
    end

    def show_position_summary
      summary = @position_tracker.get_positions_summary
      underlying_summary = @position_tracker.get_underlying_summary

      puts "\n" + "="*60
      puts "[POSITION SUMMARY]"
      puts "Total Positions: #{summary[:total_positions]}"
      puts "Total P&L: ₹#{summary[:total_pnl].round(2)}"
      puts "Available Balance: ₹#{@balance_provider.available_balance.round(0)}"

      if underlying_summary.any?
        puts "\n[UNDERLYING PRICES]"
        underlying_summary.each do |symbol, data|
          price = data[:last_price] ? "₹#{data[:last_price]}" : "N/A"
          puts "#{symbol}: #{price} (#{data[:instrument_id]})"
        end
      end

      if summary[:positions].any?
        puts "\n[POSITIONS]"
        summary[:positions].each do |key, pos|
          puts "#{key}: #{pos[:quantity]} #{pos[:option_type]} @ ₹#{pos[:entry_price]} | P&L: ₹#{pos[:pnl].round(2)}"
        end
      end

      puts "="*60
    end

    def show_final_summary
      summary = @position_tracker.get_positions_summary

      puts "\n" + "="*60
      puts "[FINAL SUMMARY]"
      puts "Session P&L: ₹#{summary[:total_pnl].round(2)}"
      puts "Final Balance: ₹#{@balance_provider.available_balance.round(0)}"
      puts "Positions Closed: #{summary[:total_positions]}"
      puts "="*60
    end

    def get_cached_trend(symbol, symbol_config)
      trend_key = "#{symbol}_trend"

      unless @cached_trends[trend_key]
        if @enhanced
          use_multi_timeframe = @cfg.dig("global", "use_multi_timeframe") != false
          secondary_timeframe = @cfg.dig("global", "secondary_timeframe") || 5
          @cached_trends[trend_key] = TrendEnhanced.new(
            seg_idx: symbol_config["seg_idx"],
            sid_idx: symbol_config["idx_sid"],
            use_multi_timeframe: use_multi_timeframe,
            secondary_timeframe: secondary_timeframe
          )
        else
          @cached_trends[trend_key] = Trend.new(
            seg_idx: symbol_config["seg_idx"],
            sid_idx: symbol_config["idx_sid"]
          )
        end
      end

      @cached_trends[trend_key]
    end

    def get_cached_picker(symbol, symbol_config)
      picker_key = "#{symbol}_picker"

      unless @cached_pickers[picker_key]
        @cached_pickers[picker_key] = OptionPicker.new(symbol_config, mode: :paper)
      end

      @cached_pickers[picker_key]
    end

    def sym_cfg(sym)
      @cfg["SYMBOLS"][sym] || {}
    end
  end
end
