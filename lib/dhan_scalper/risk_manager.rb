# frozen_string_literal: true

require "concurrent"
require_relative "tick_cache"
require_relative "position"

module DhanScalper
  class RiskManager
    def initialize(config, position_tracker, broker, logger: nil)
      @config = config
      @position_tracker = position_tracker
      @broker = broker
      @logger = logger || Logger.new($stdout)
      @running = false
      @risk_thread = nil

      # Risk parameters
      @tp_pct = config.dig("global", "tp_pct") || 0.35
      @sl_pct = config.dig("global", "sl_pct") || 0.18
      @trail_pct = config.dig("global", "trail_pct") || 0.12
      @charge_per_order = config.dig("global", "charge_per_order") || 20.0
      @risk_check_interval = config.dig("global", "risk_check_interval") || 1

      # Position tracking for trailing stops
      @position_highs = Concurrent::Map.new
    end

    def start
      return if @running

      @running = true
      @logger.info "[RISK] Starting risk management loop (interval: #{@risk_check_interval}s)"

      @risk_thread = Thread.new do
        risk_loop
      end
    end

    def stop
      return unless @running

      @running = false
      @risk_thread&.join(2)
      @logger.info "[RISK] Risk management stopped"
    end

    def running?
      @running
    end

    private

    def risk_loop
      while @running
        begin
          check_all_positions
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
      @position_tracker.update_position(security_id, { current_price: current_price })

      # Calculate PnL
      pnl = calculate_pnl(position, current_price)
      pnl_pct = calculate_pnl_percentage(position, current_price)

      # Update position high for trailing stops
      update_position_high(security_id, current_price)

      # Check exit conditions
      exit_reason = determine_exit_reason(position, current_price, pnl, pnl_pct)

      if exit_reason
        exit_position(position, current_price, exit_reason)
      else
        # Log position status
        @logger.debug "[RISK] #{position[:symbol]} #{position[:option_type]} " \
                      "LTP: #{current_price.round(2)} PnL: #{pnl.round(0)} " \
                      "(#{pnl_pct.round(1)}%)"
      end
    end

    def get_current_price(security_id)
      # Try to get price from tick cache first
      price = TickCache.ltp("NSE_FNO", security_id)
      return price if price&.positive?

      # Fallback: try to get from broker or API
      # This would need to be implemented based on the broker
      nil
    end

    def calculate_pnl(position, current_price)
      entry_price = position[:entry_price]
      quantity = position[:quantity]

      # For options buying, PnL = (current_price - entry_price) * quantity
      (current_price - entry_price) * quantity
    end

    def calculate_pnl_percentage(position, current_price)
      entry_price = position[:entry_price]
      return 0.0 if entry_price.zero?

      ((current_price - entry_price) / entry_price) * 100
    end

    def update_position_high(security_id, current_price)
      current_high = @position_highs[security_id] || 0.0
      @position_highs[security_id] = [current_high, current_price].max
    end

    def determine_exit_reason(position, current_price, _pnl, pnl_pct)
      position[:entry_price]
      security_id = position[:security_id]

      # Take Profit
      return "TP" if pnl_pct >= (@tp_pct * 100)

      # Stop Loss
      return "SL" if pnl_pct <= -(@sl_pct * 100)

      # Trailing Stop
      return "TRAIL" if should_trail_stop?(position, current_price, security_id)

      # Session target reached (this would need to be passed from the main app)
      # For now, we'll skip this check as it's handled at a higher level

      nil
    end

    def should_trail_stop?(position, current_price, security_id)
      entry_price = position[:entry_price]
      position_high = @position_highs[security_id] || entry_price

      # Check if we've hit the trailing trigger
      trail_trigger_price = entry_price * (1.0 + @trail_pct)

      if position_high >= trail_trigger_price
        # We're in profit, check if current price has fallen below trailing stop
        trail_stop_price = position_high * (1.0 - (@trail_pct / 2.0))
        return current_price <= trail_stop_price
      end

      false
    end

    def exit_position(position, current_price, reason)
      security_id = position[:security_id]
      quantity = position[:quantity]

      @logger.info "[RISK] Exiting position #{position[:symbol]} #{position[:option_type]} " \
                   "reason: #{reason} LTP: #{current_price.round(2)}"

      begin
        # Place sell order
        order = @broker.sell_market(
          segment: "NSE_FNO",
          security_id: security_id,
          quantity: quantity
        )

        if order
          # Calculate final PnL including charges
          final_pnl = calculate_pnl(position, current_price) - @charge_per_order

          # Update position tracker
          @position_tracker.close_position(security_id, {
                                             exit_price: current_price,
                                             exit_reason: reason,
                                             final_pnl: final_pnl,
                                             exit_timestamp: Time.now
                                           })

          @logger.info "[RISK] Position closed: #{position[:symbol]} " \
                       "Final PnL: ₹#{final_pnl.round(2)}"
        else
          @logger.error "[RISK] Failed to place exit order for #{security_id}"
        end
      rescue StandardError => e
        @logger.error "[RISK] Error exiting position #{security_id}: #{e.message}"
      ensure
        # Clean up position high tracking
        @position_highs.delete(security_id)
      end
    end
  end
end
