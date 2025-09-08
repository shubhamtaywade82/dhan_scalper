# frozen_string_literal: true

require_relative "../support/application_service"

module DhanScalper
  module Managers
    # Entry manager for handling new position entries
    class EntryManager < DhanScalper::ApplicationService
      attr_reader :config, :trend_filter, :sizing_calculator, :order_manager, :position_tracker

      def initialize(config:, trend_filter:, sizing_calculator:, order_manager:, position_tracker:)
        @config = config
        @trend_filter = trend_filter
        @sizing_calculator = sizing_calculator
        @order_manager = order_manager
        @position_tracker = position_tracker
      end

      def call(symbol, spot_price)
        return :market_closed unless market_open?
        return :max_positions_reached if max_positions_reached?
        return :insufficient_budget unless sufficient_budget?

        # Check trend streak
        return :trend_streak_failed unless trend_streak_valid?(symbol)

        # Get trend signal
        signal = @trend_filter.get_signal(symbol, spot_price)
        return :no_signal unless signal && signal != :none

        # Pick strike and calculate size
        strike_info = pick_strike(symbol, spot_price, signal)
        return :no_strike_available unless strike_info

        # Calculate position size
        size_info = @sizing_calculator.calculate(
          symbol: symbol,
          premium: strike_info[:premium],
          side: signal == :long ? "BUY" : "SELL"
        )
        return :insufficient_size unless size_info[:quantity] >= 1

        # Place entry order
        place_entry_order(symbol, signal, strike_info, size_info)
      end

      private

      def market_open?
        current_time = Time.now
        market_start = Time.parse("09:15")
        market_end = Time.parse("15:30")

        # Add grace period
        grace_start = market_start - 5.minutes
        grace_end = market_end + 5.minutes

        current_time >= grace_start && current_time <= grace_end
      end

      def max_positions_reached?
        max_positions = @config.dig("risk", "max_concurrent_positions")&.to_i || 5
        open_positions = @position_tracker.get_open_positions
        open_positions.size >= max_positions
      end

      def sufficient_budget?
        # This would check available balance
        # For now, assume sufficient budget
        true
      end

      def trend_streak_valid?(symbol)
        streak_window = @config.dig("trend", "streak_window_minutes")&.to_i || 5

        # Check if trend has been ON for the required duration
        trend_key = "trend_streak:#{symbol}"
        streak_start = @trend_filter.get_streak_start(symbol)

        return false unless streak_start

        (Time.now - streak_start) >= (streak_window * 60)
      end

      def pick_strike(symbol, spot_price, signal)
        symbol_config = @config.dig("SYMBOLS", symbol)
        return nil unless symbol_config

        # Get ATM strike
        atm_strike = calculate_atm_strike(spot_price, symbol_config)
        return nil unless atm_strike

        # Apply ATM window
        atm_window = symbol_config.dig("atm_window_pct")&.to_f || 0.02
        strike_range = spot_price * atm_window

        # Pick strike within range
        strikes = get_available_strikes(symbol, atm_strike, strike_range)
        return nil if strikes.empty?

        selected_strike = select_best_strike(strikes, spot_price, signal)
        return nil unless selected_strike

        # Calculate premium (simplified)
        premium = calculate_premium(selected_strike, spot_price, signal)

        {
          strike: selected_strike,
          premium: premium,
          option_type: signal == :long ? "CE" : "PE",
          security_id: get_security_id(symbol, selected_strike, signal == :long ? "CE" : "PE")
        }
      end

      def calculate_atm_strike(spot_price, symbol_config)
        strike_step = symbol_config.dig("strike_step")&.to_i || 50
        (spot_price / strike_step).round * strike_step
      end

      def get_available_strikes(symbol, atm_strike, strike_range)
        # This would integrate with CSV master to get available strikes
        # For now, return a simple range
        min_strike = atm_strike - strike_range
        max_strike = atm_strike + strike_range

        strikes = []
        strike_step = 50

        current = (min_strike / strike_step).ceil * strike_step
        while current <= max_strike
          strikes << current
          current += strike_step
        end

        strikes
      end

      def select_best_strike(strikes, spot_price, signal)
        # Simple selection: closest to ATM
        strikes.min_by { |strike| (strike - spot_price).abs }
      end

      def calculate_premium(strike, spot_price, signal)
        # Simplified premium calculation
        moneyness = (strike - spot_price) / spot_price
        base_premium = spot_price * 0.01 # 1% of spot as base

        case signal
        when :long
          # For CE, higher strike = lower premium
          base_premium * (1 - moneyness.abs)
        when :short
          # For PE, lower strike = lower premium
          base_premium * (1 - moneyness.abs)
        end
      end

      def get_security_id(symbol, strike, option_type)
        # This would integrate with CSV master
        # For now, return a mock ID
        "#{symbol}_#{strike}_#{option_type}_#{Time.now.to_i}"
      end

      def place_entry_order(symbol, signal, strike_info, size_info)
        order_data = {
          symbol: symbol,
          security_id: strike_info[:security_id],
          side: signal == :long ? "BUY" : "SELL",
          quantity: size_info[:quantity],
          price: strike_info[:premium],
          order_type: "MARKET",
          option_type: strike_info[:option_type],
          strike: strike_info[:strike]
        }

        result = @order_manager.place_order(order_data)

        if result[:success]
          puts "[ENTRY] Placed #{signal} order: #{symbol} #{strike_info[:option_type]} #{strike_info[:strike]} @ ₹#{strike_info[:premium].round(2)}"
          :success
        else
          puts "[ENTRY] Failed to place order: #{result[:error]}"
          :order_failed
        end
      end
    end
  end
end
