# frozen_string_literal: true

require "concurrent"
require "securerandom"
require_relative "tick_cache"
require_relative "position"
require_relative "config"
require_relative "support/money"
require_relative "support/logger"
require_relative "support/validations"

module DhanScalper
  class UnifiedRiskManager
    def initialize(config, position_tracker, broker, balance_provider: nil, equity_calculator: nil, logger: nil)
      @config = config
      @position_tracker = position_tracker
      @broker = broker
      @balance_provider = balance_provider
      @equity_calculator = equity_calculator
      @logger = logger || DhanScalper::Support::Logger
      @running = false
      @risk_thread = nil

      # Basic risk parameters
      @tp_pct = config.dig("global", "tp_pct") || 0.35
      @sl_pct = config.dig("global", "sl_pct") || 0.18
      @trail_pct = config.dig("global", "trail_pct") || 0.12
      @charge_per_order = DhanScalper::Config.fee
      @risk_check_interval = config.dig("global", "risk_check_interval") || 1

      # Enhanced risk management features
      @time_stop_seconds = config.dig("global", "time_stop_seconds") || 300
      @max_daily_loss_rs = DhanScalper::Support::Money.bd(config.dig("global", "max_daily_loss_rs") || 2_000.0)
      @cooldown_after_loss_seconds = config.dig("global", "cooldown_after_loss_seconds") || 180
      @enable_time_stop = config.dig("global", "enable_time_stop") != false
      @enable_daily_loss_cap = config.dig("global", "enable_daily_loss_cap") != false
      @enable_cooldown = config.dig("global", "enable_cooldown") != false

      # Position tracking
      @position_highs = Concurrent::Map.new
      @position_entry_times = Concurrent::Map.new
      @position_profits = Concurrent::Map.new

      # Session tracking
      @session_start_equity = nil
      @last_loss_time = nil
      @in_cooldown = false

      # Idempotency tracking - prevents duplicate orders
      @idempotency_keys = Concurrent::Map.new
      @pending_exits = Concurrent::Map.new
    end

    def start
      return if @running

      @running = true
      @session_start_equity ||= get_current_equity
      @last_loss_time = nil
      @in_cooldown = false

      @logger.info(
        "Starting unified risk management loop (interval: #{@risk_check_interval}s)",
        component: "RiskManager",
      )
      @logger.info(
        "Time stop: #{@enable_time_stop ? "#{@time_stop_seconds}s" : "disabled"}",
        component: "RiskManager",
      )
      @logger.info(
        "Daily loss cap: #{@enable_daily_loss_cap ? "₹#{DhanScalper::Support::Money.dec(@max_daily_loss_rs)}" : "disabled"}",
        component: "RiskManager",
      )
      @logger.info(
        "Cooldown: #{@enable_cooldown ? "#{@cooldown_after_loss_seconds}s" : "disabled"}",
        component: "RiskManager",
      )

      @risk_thread = Thread.new do
        risk_loop
      end
    end

    def stop
      return unless @running

      @running = false
      @risk_thread&.join(2)
      @logger.info("Risk management stopped", component: "RiskManager")
    end

    def running?
      @running
    end

    def reset_session
      @session_start_equity = get_current_equity
      @last_loss_time = nil
      @in_cooldown = false
      @logger.info(
        "Session reset, starting equity: ₹#{DhanScalper::Support::Money.dec(@session_start_equity)}",
        component: "RiskManager",
      )
    end

    private

    def risk_loop
      while @running
        begin
          # Check daily loss cap first (highest priority)
          check_daily_loss_cap

          # Skip individual position checks if in cooldown
          check_all_positions unless in_cooldown?

          sleep(@risk_check_interval)
        rescue StandardError => e
          @logger.error("Risk management error: #{e.message}", component: "RiskManager")
          @logger.error(e.backtrace.join("\n"), component: "RiskManager")
          sleep(@risk_check_interval)
        end
      end
    end

    def check_daily_loss_cap
      return unless @enable_daily_loss_cap
      return unless @session_start_equity

      current_equity = get_current_equity
      equity_drawdown = DhanScalper::Support::Money.subtract(@session_start_equity, current_equity)

      @logger.debug(
        "Daily loss cap check: start=₹#{DhanScalper::Support::Money.dec(@session_start_equity)}, " \
        "current=₹#{DhanScalper::Support::Money.dec(current_equity)}, " \
        "drawdown=₹#{DhanScalper::Support::Money.dec(equity_drawdown)}, " \
        "max=₹#{DhanScalper::Support::Money.dec(@max_daily_loss_rs)}",
        component: "RiskManager",
      )

      return unless DhanScalper::Support::Money.greater_than?(equity_drawdown, @max_daily_loss_rs)

      @logger.warn(
        "Daily loss cap exceeded! Drawdown: ₹#{DhanScalper::Support::Money.dec(equity_drawdown)} " \
        "(max: ₹#{DhanScalper::Support::Money.dec(@max_daily_loss_rs)})",
        component: "RiskManager",
      )

      # Close all positions
      close_all_positions("DAILY_LOSS_CAP")
    end

    def in_cooldown?
      return false unless @enable_cooldown
      return false unless @last_loss_time

      time_since_loss = Time.now - @last_loss_time
      @in_cooldown = time_since_loss < @cooldown_after_loss_seconds

      if @in_cooldown
        remaining = @cooldown_after_loss_seconds - time_since_loss
        @logger.debug("In cooldown, #{remaining.round(1)}s remaining", component: "RiskManager")
      end

      @in_cooldown
    end

    def check_all_positions
      positions = @position_tracker.get_positions
      return if positions.empty?

      positions.each do |position|
        next unless position[:net_qty] && DhanScalper::Support::Money.positive?(position[:net_qty])

        check_position_risks(position)
      end
    end

    def check_position_risks(position)
      security_id = position[:security_id]
      current_price = DhanScalper::TickCache.ltp(position[:exchange_segment], security_id)
      return unless current_price&.positive?

      # Update position tracking
      update_position_tracking(security_id, current_price, position)

      # Check for exit triggers
      exit_reason = determine_exit_reason(position, security_id, current_price)
      return unless exit_reason

      # Execute exit with idempotency
      execute_exit(position, security_id, current_price, exit_reason)
    end

    def update_position_tracking(security_id, current_price, position)
      price_bd = DhanScalper::Support::Money.bd(current_price)
      entry_price = position[:buy_avg]

      # Track position high for trailing stops
      current_high = @position_highs[security_id] || price_bd
      if DhanScalper::Support::Money.greater_than?(price_bd, current_high)
        @position_highs[security_id] = price_bd
      end

      # Track entry time for time stops
      @position_entry_times[security_id] ||= Time.now

      # Calculate current P&L
      pnl = DhanScalper::Support::Money.multiply(
        DhanScalper::Support::Money.subtract(price_bd, entry_price),
        position[:net_qty],
      )
      @position_profits[security_id] = pnl
    end

    def determine_exit_reason(position, security_id, current_price)
      # Skip if in cooldown (except for emergency exits)
      return nil if in_cooldown?

      # Take Profit
      if should_take_profit?(position, current_price)
        return "TAKE_PROFIT"
      end

      # Stop Loss
      if should_stop_loss?(position, current_price)
        return "STOP_LOSS"
      end

      # Time Stop
      if should_time_stop?(security_id)
        return "TIME_STOP"
      end

      # Trailing Stop
      if should_trailing_stop?(position, security_id, current_price)
        return "TRAILING_STOP"
      end

      nil
    end

    def should_take_profit?(position, current_price)
      return false unless position[:buy_avg]

      price_bd = DhanScalper::Support::Money.bd(current_price)
      entry_price = position[:buy_avg]
      profit_pct = DhanScalper::Support::Money.divide(
        DhanScalper::Support::Money.subtract(price_bd, entry_price),
        entry_price,
      )

      DhanScalper::Support::Money.greater_than?(profit_pct, DhanScalper::Support::Money.bd(@tp_pct))
    end

    def should_stop_loss?(position, current_price)
      return false unless position[:buy_avg]

      price_bd = DhanScalper::Support::Money.bd(current_price)
      entry_price = position[:buy_avg]
      loss_pct = DhanScalper::Support::Money.divide(
        DhanScalper::Support::Money.subtract(entry_price, price_bd),
        entry_price,
      )

      DhanScalper::Support::Money.greater_than?(loss_pct, DhanScalper::Support::Money.bd(@sl_pct))
    end

    def should_time_stop?(security_id)
      return false unless @enable_time_stop

      entry_time = @position_entry_times[security_id]
      return false unless entry_time

      time_in_position = Time.now - entry_time
      time_in_position >= @time_stop_seconds
    end

    def should_trailing_stop?(position, security_id, current_price)
      return false unless position[:buy_avg]

      price_bd = DhanScalper::Support::Money.bd(current_price)
      entry_price = position[:buy_avg]
      position_high = @position_highs[security_id] || price_bd

      # Only trigger if price has moved up from entry
      return false unless DhanScalper::Support::Money.greater_than?(position_high, entry_price)

      # Check if current price has fallen from high by trail percentage
      trail_threshold = DhanScalper::Support::Money.multiply(
        position_high,
        DhanScalper::Support::Money.bd(@trail_pct),
      )
      trail_trigger = DhanScalper::Support::Money.subtract(position_high, trail_threshold)

      DhanScalper::Support::Money.less_than?(price_bd, trail_trigger)
    end

    def execute_exit(position, security_id, current_price, reason)
      # Check idempotency - prevent duplicate exits
      idempotency_key = generate_idempotency_key(security_id, reason)

      if @pending_exits[security_id] || @idempotency_keys[idempotency_key]
        @logger.debug(
          "Exit already pending or completed for #{security_id} (#{reason}), skipping",
          component: "RiskManager",
        )
        return
      end

      # Mark as pending
      @pending_exits[security_id] = {
        reason: reason,
        timestamp: Time.now,
        idempotency_key: idempotency_key,
      }

      @logger.info(
        "Exiting position #{security_id} reason: #{reason} LTP: #{DhanScalper::Support::Money.dec(DhanScalper::Support::Money.bd(current_price))}",
        component: "RiskManager",
      )

      begin
        # Place sell order with idempotency
        order_result = @broker.place_order!(
          symbol: security_id,
          instrument_id: security_id,
          side: "SELL",
          quantity: DhanScalper::Support::Money.dec(position[:net_qty]),
          price: current_price,
          order_type: "MARKET",
          idempotency_key: idempotency_key,
        )

        if order_result && order_result[:order_status] == "FILLED"
          # Track the idempotency key to prevent duplicates
          @idempotency_keys[idempotency_key] = {
            security_id: security_id,
            reason: reason,
            timestamp: Time.now,
            order_id: order_result[:order_id],
          }

          # Update position tracker
          @position_tracker.partial_exit(
            exchange_segment: position[:exchange_segment],
            security_id: security_id,
            side: "LONG",
            quantity: DhanScalper::Support::Money.dec(position[:net_qty]),
            price: current_price,
            fee: @charge_per_order,
          )

          # Calculate final P&L
          final_pnl = calculate_final_pnl(position, current_price)

          # Track loss for cooldown
          if DhanScalper::Support::Money.negative?(final_pnl)
            @last_loss_time = Time.now
            @in_cooldown = true
            @logger.info("Loss detected, starting cooldown period", component: "RiskManager")
          end

          # Clean up tracking
          cleanup_position_tracking(security_id)
        else
          @logger.error("Failed to exit position #{security_id}: #{order_result}", component: "RiskManager")
        end
      rescue StandardError => e
        @logger.error("Error exiting position #{security_id}: #{e.message}", component: "RiskManager")
      ensure
        # Always remove from pending
        @pending_exits.delete(security_id)
      end
    end

    def generate_idempotency_key(security_id, reason)
      timestamp = Time.now.to_i
      random = SecureRandom.hex(4)
      "risk_exit_#{security_id}_#{reason}_#{timestamp}_#{random}"
    end

    def calculate_final_pnl(position, exit_price)
      entry_price = position[:buy_avg]
      quantity = position[:net_qty]

      DhanScalper::Support::Money.multiply(
        DhanScalper::Support::Money.subtract(
          DhanScalper::Support::Money.bd(exit_price),
          entry_price,
        ),
        quantity,
      )
    end

    def cleanup_position_tracking(security_id)
      @position_highs.delete(security_id)
      @position_entry_times.delete(security_id)
      @position_profits.delete(security_id)
    end

    def close_all_positions(reason)
      positions = @position_tracker.get_positions
      positions.each do |position|
        next unless position[:net_qty] && DhanScalper::Support::Money.positive?(position[:net_qty])

        current_price = DhanScalper::TickCache.ltp(position[:exchange_segment], position[:security_id])
        next unless current_price&.positive?

        execute_exit(position, position[:security_id], current_price, reason)
      end
    end

    def get_current_equity
      if @equity_calculator
        @equity_calculator.get_total_equity
      elsif @balance_provider
        @balance_provider.total_balance
      else
        DhanScalper::Support::Money.bd(0)
      end
    end
  end
end
