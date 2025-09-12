# frozen_string_literal: true

require "concurrent"
require "securerandom"
require_relative "tick_cache"
require_relative "position"
require_relative "config"
require_relative "support/money"

module DhanScalper
  class EnhancedRiskManager
    def initialize(config, position_tracker, broker, balance_provider, equity_calculator, logger: nil)
      @config = config
      @position_tracker = position_tracker
      @broker = broker
      @balance_provider = balance_provider
      @equity_calculator = equity_calculator
      @logger = logger || Logger.new($stdout)
      @running = false
      @risk_thread = nil

      # Risk parameters from config
      @tp_pct = config.dig("global", "tp_pct") || 0.35
      @sl_pct = config.dig("global", "sl_pct") || 0.18
      @trail_pct = config.dig("global", "trail_pct") || 0.12
      @charge_per_order = DhanScalper::Config.fee
      @risk_check_interval = config.dig("global", "risk_check_interval") || 1

      # New risk manager features
      @time_stop_seconds = config.dig("global", "time_stop_seconds") || 300
      @max_daily_loss_rs = DhanScalper::Support::Money.bd(config.dig("global", "max_daily_loss_rs") || 2000.0)
      @cooldown_after_loss_seconds = config.dig("global", "cooldown_after_loss_seconds") || 180
      @enable_time_stop = config.dig("global", "enable_time_stop") != false
      @enable_daily_loss_cap = config.dig("global", "enable_daily_loss_cap") != false
      @enable_cooldown = config.dig("global", "enable_cooldown") != false

      # Position tracking for trailing stops and time stops
      @position_highs = Concurrent::Map.new
      @position_entry_times = Concurrent::Map.new
      @position_profits = Concurrent::Map.new

      # Session tracking
      @session_start_equity = nil
      @last_loss_time = nil
      @in_cooldown = false

      # Idempotency tracking
      @idempotency_keys = Concurrent::Map.new
    end

    def start
      return if @running

      @running = true
      # Only set session start equity if it hasn't been set yet
      unless @session_start_equity
        @session_start_equity = get_current_equity
      end
      @last_loss_time = nil
      @in_cooldown = false

      @logger.info "[RISK] Starting enhanced risk management loop (interval: #{@risk_check_interval}s)"
      @logger.info "[RISK] Time stop: #{@enable_time_stop ? "#{@time_stop_seconds}s" : 'disabled'}"
      @logger.info "[RISK] Daily loss cap: #{@enable_daily_loss_cap ? "₹#{DhanScalper::Support::Money.dec(@max_daily_loss_rs)}" : 'disabled'}"
      @logger.info "[RISK] Cooldown: #{@enable_cooldown ? "#{@cooldown_after_loss_seconds}s" : 'disabled'}"

      @risk_thread = Thread.new do
        risk_loop
      end
    end

    def stop
      return unless @running

      @running = false
      @risk_thread&.join(2)
      @logger.info "[RISK] Enhanced risk management stopped"
    end

    def running?
      @running
    end

    def in_cooldown?
      return false unless @enable_cooldown
      return false unless @last_loss_time

      time_since_loss = Time.now - @last_loss_time
      @in_cooldown = time_since_loss < @cooldown_after_loss_seconds

      if @in_cooldown
        remaining = @cooldown_after_loss_seconds - time_since_loss
        @logger.debug "[RISK] In cooldown, #{remaining.round(1)}s remaining"
      end

      @in_cooldown
    end

    def reset_session
      current_equity = get_current_equity
      @session_start_equity = current_equity
      @last_loss_time = nil
      @in_cooldown = false
      @logger.info "[RISK] Session reset, starting equity: ₹#{DhanScalper::Support::Money.dec(@session_start_equity)}"
    end

    private

    def risk_loop
      while @running
        begin
          # Check daily loss cap first (highest priority)
          check_daily_loss_cap

          # Skip individual position checks if in cooldown
          unless check_cooldown_status
            check_all_positions
          end

          sleep(@risk_check_interval)
        rescue StandardError => e
          @logger.error "[RISK] Error in risk loop: #{e.message}"
          @logger.error "[RISK] Backtrace: #{e.backtrace.first(3).join("\n")}"
          sleep(5) # Wait before retrying
        end
      end
    end

    def check_all_positions
      positions = @position_tracker.get_positions
      return if positions.empty?

      positions.each do |position|
        check_position_risk(position)
      end
    end

    def check_position_risk(position)
      security_id = position[:security_id]
      current_price = get_current_price(security_id)

      return unless current_price&.positive?

      # Update position with current price
      @position_tracker.update_current_price(
        exchange_segment: position[:exchange_segment] || "NSE_EQ",
        security_id: security_id,
        side: position[:side] || "LONG",
        current_price: current_price
      )

      # Calculate PnL
      pnl = calculate_pnl(position, current_price)
      pnl_pct = calculate_pnl_percentage(position, current_price)

      # Update position high for trailing stops
      update_position_high(security_id, current_price)

      # Track position entry time for time stops
      track_position_entry_time(security_id, position)

      # Check exit conditions
      exit_reason = determine_exit_reason(position, current_price, pnl, pnl_pct)

      if exit_reason
        exit_position(position, current_price, exit_reason)
      else
        # Log position status
        @logger.debug "[RISK] #{security_id} LTP: #{DhanScalper::Support::Money.dec(current_price)} PnL: #{DhanScalper::Support::Money.dec(pnl)} (#{pnl_pct.round(1)}%)"
      end
    end

    def check_daily_loss_cap
      return unless @enable_daily_loss_cap
      return unless @session_start_equity

      current_equity = get_current_equity
      equity_drawdown = DhanScalper::Support::Money.subtract(@session_start_equity, current_equity)

      @logger.debug "[RISK] Daily loss cap check: start=₹#{DhanScalper::Support::Money.dec(@session_start_equity)}, current=₹#{DhanScalper::Support::Money.dec(current_equity)}, drawdown=₹#{DhanScalper::Support::Money.dec(equity_drawdown)}, max=₹#{DhanScalper::Support::Money.dec(@max_daily_loss_rs)}"

      if DhanScalper::Support::Money.greater_than?(equity_drawdown, @max_daily_loss_rs)
        @logger.warn "[RISK] Daily loss cap exceeded! Drawdown: ₹#{DhanScalper::Support::Money.dec(equity_drawdown)} (max: ₹#{DhanScalper::Support::Money.dec(@max_daily_loss_rs)})"

        # Close all positions
        close_all_positions("DAILY_LOSS_CAP")
      end
    end

    def check_cooldown_status
      if in_cooldown?
        @logger.debug "[RISK] In cooldown period, skipping new position checks"
        return true
      end

      false
    end

    def get_current_price(security_id)
      # Try to get price from tick cache first
      price = TickCache.ltp("NSE_EQ", security_id)
      return price if price&.positive?

      # Fallback: try to get from broker or API
      nil
    end

    def calculate_pnl(position, current_price)
      entry_price = position[:buy_avg] || position[:entry_price]
      quantity = position[:net_qty] || position[:quantity]

      return 0.0 unless entry_price && quantity

      # For long positions, PnL = (current_price - entry_price) * quantity
      DhanScalper::Support::Money.multiply(
        DhanScalper::Support::Money.subtract(current_price, entry_price),
        quantity
      )
    end

    def calculate_pnl_percentage(position, current_price)
      entry_price = position[:buy_avg] || position[:entry_price]
      return 0.0 if entry_price.nil? || DhanScalper::Support::Money.zero?(entry_price)

      pnl = DhanScalper::Support::Money.subtract(current_price, entry_price)
      DhanScalper::Support::Money.multiply(
        DhanScalper::Support::Money.divide(pnl, entry_price),
        DhanScalper::Support::Money.bd(100)
      )
    end

    def update_position_high(security_id, current_price)
      current_high = @position_highs[security_id] || DhanScalper::Support::Money.bd(0)
      @position_highs[security_id] = DhanScalper::Support::Money.max(current_high, current_price)
    end

    def track_position_entry_time(security_id, position)
      return if @position_entry_times[security_id]

      @position_entry_times[security_id] = position[:created_at] || Time.now
    end

    def determine_exit_reason(position, current_price, pnl, pnl_pct)
      security_id = position[:security_id]

      # Skip if in cooldown (except for emergency exits)
      return nil if in_cooldown?

      # Take Profit
      return "TP" if DhanScalper::Support::Money.greater_than_or_equal?(pnl_pct, DhanScalper::Support::Money.bd(@tp_pct * 100))

      # Stop Loss
      return "SL" if DhanScalper::Support::Money.less_than_or_equal?(pnl_pct, DhanScalper::Support::Money.bd(-@sl_pct * 100))

      # Time Stop
      return "TIME_STOP" if should_time_stop?(security_id)

      # Trailing Stop
      return "TRAIL" if should_trail_stop?(position, current_price, security_id)

      nil
    end

    def should_time_stop?(security_id)
      return false unless @enable_time_stop

      entry_time = @position_entry_times[security_id]
      return false unless entry_time

      time_in_position = Time.now - entry_time
      time_in_position >= @time_stop_seconds
    end

    def should_trail_stop?(position, current_price, security_id)
      entry_price = position[:buy_avg] || position[:entry_price]
      position_high = @position_highs[security_id] || entry_price

      # Check if we've hit the trailing trigger
      trail_trigger_price = DhanScalper::Support::Money.multiply(
        entry_price,
        DhanScalper::Support::Money.bd(1.0 + @trail_pct)
      )

      if DhanScalper::Support::Money.greater_than_or_equal?(position_high, trail_trigger_price)
        # We're in profit, check if current price has fallen below trailing stop
        trail_stop_price = DhanScalper::Support::Money.multiply(
          position_high,
          DhanScalper::Support::Money.bd(1.0 - (@trail_pct / 2.0))
        )
        return DhanScalper::Support::Money.less_than_or_equal?(current_price, trail_stop_price)
      end

      false
    end

    def exit_position(position, current_price, reason)
      security_id = position[:security_id]
      quantity = position[:net_qty] || position[:quantity]

      @logger.info "[RISK] Exiting position #{security_id} reason: #{reason} LTP: #{DhanScalper::Support::Money.dec(current_price)}"

      begin
        # Generate idempotency key
        idempotency_key = generate_idempotency_key(security_id, reason)

        # Place sell order with idempotency
        order_result = @broker.place_order!(
          symbol: security_id,
          instrument_id: security_id,
          side: "SELL",
          quantity: quantity,
          price: current_price,
          order_type: "MARKET",
          idempotency_key: idempotency_key
        )

        if order_result && order_result[:order_status] == "FILLED"
          # Calculate final PnL including charges
          final_pnl = DhanScalper::Support::Money.subtract(
            calculate_pnl(position, current_price),
            @charge_per_order
          )

          # Update position tracker
          @position_tracker.partial_exit(
            exchange_segment: position[:exchange_segment] || "NSE_EQ",
            security_id: security_id,
            side: position[:side] || "LONG",
            quantity: quantity,
            price: current_price
          )

          # Track loss for cooldown
          if DhanScalper::Support::Money.negative?(final_pnl)
            @last_loss_time = Time.now
            @in_cooldown = true
            @logger.info "[RISK] Loss detected, starting cooldown period"
          end

          @logger.info "[RISK] Position closed: #{security_id} Final PnL: ₹#{DhanScalper::Support::Money.dec(final_pnl)}"
        else
          @logger.error "[RISK] Failed to place exit order for #{security_id}: #{order_result&.dig(:error)}"
        end
      rescue StandardError => e
        @logger.error "[RISK] Error exiting position #{security_id}: #{e.message}"
      ensure
        # Clean up position tracking
        @position_highs.delete(security_id)
        @position_entry_times.delete(security_id)
        @position_profits.delete(security_id)
      end
    end

    def close_all_positions(reason)
      positions = @position_tracker.get_positions
      return if positions.empty?

      @logger.warn "[RISK] Closing all positions due to #{reason}"

      positions.each do |position|
        security_id = position[:security_id]
        current_price = get_current_price(security_id)

        if current_price&.positive?
          exit_position(position, current_price, reason)
        else
          @logger.warn "[RISK] Unable to get current price for #{security_id}, skipping"
        end
      end
    end

    def generate_idempotency_key(security_id, reason)
      timestamp = Time.now.to_i
      random = SecureRandom.hex(4)
      "risk_exit_#{security_id}_#{reason}_#{timestamp}_#{random}"
    end

    def get_current_equity
      equity = @equity_calculator.calculate_equity
      equity[:total_equity]
    end
  end
end
