# frozen_string_literal: true

require_relative "../support/application_service"

module DhanScalper
  module Managers
    # Entry manager for handling new position entries
    class EntryManager < DhanScalper::ApplicationService
      attr_reader :config, :trend_filter, :sizing_calculator, :order_manager, :position_tracker

      def initialize(config:, trend_filter:, sizing_calculator:, order_manager:, position_tracker:, csv_master: nil,
                     logger: Logger.new($stdout))
        @config = config
        @trend_filter = trend_filter
        @sizing_calculator = sizing_calculator
        @order_manager = order_manager
        @position_tracker = position_tracker
        @csv_master = csv_master
        @logger = logger
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
        return :insufficient_size unless size_info[:quantity].to_i >= 1

        # Place entry order
        place_entry_order(symbol, signal, strike_info, size_info)
      end

      private

      def market_open?
        now = Time.now
        start_h = 9
        start_m = 15
        end_h = 15
        end_m = 30
        grace_seconds = 5 * 60

        start_ts = Time.new(now.year, now.month, now.day, start_h, start_m, 0, now.utc_offset)
        end_ts   = Time.new(now.year, now.month, now.day, end_h, end_m, 0, now.utc_offset)

        (now >= (start_ts - grace_seconds)) && (now <= (end_ts + grace_seconds))
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
        return simple_strikes(atm_strike, strike_range) unless @csv_master

        begin
          expiry = @csv_master.get_expiry_dates(symbol)&.first
          return simple_strikes(atm_strike, strike_range) unless expiry

          strikes = @csv_master.get_available_strikes(symbol, expiry)
          return simple_strikes(atm_strike, strike_range) if strikes.nil? || strikes.empty?

          window_min = atm_strike - strike_range
          window_max = atm_strike + strike_range
          strikes.select { |s| s >= window_min && s <= window_max }
        rescue StandardError => e
          @logger.warn("[ENTRY] CSV master unavailable (#{e.message}); using simple ATM window")
          simple_strikes(atm_strike, strike_range)
        end
      end

      def select_best_strike(strikes, spot_price, _signal)
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
        return "#{symbol}_#{strike}_#{option_type}_#{Time.now.to_i}" unless @csv_master

        expiry = begin
          list = @csv_master.get_expiry_dates(symbol)
          list&.first
        rescue StandardError
          nil
        end
        begin
          sid = expiry ? @csv_master.get_security_id(symbol, expiry, strike, option_type) : nil
        rescue StandardError => e
          @logger.warn("[ENTRY] CSV master SID lookup failed: #{e.message}; using mock ID")
          sid = nil
        end
        sid || "#{symbol}_#{strike}_#{option_type}_#{Time.now.to_i}"
      end

      def simple_strikes(atm_strike, strike_range)
        min_strike = atm_strike - strike_range
        max_strike = atm_strike + strike_range
        strikes = []
        step = 50
        current = (min_strike / step).ceil * step
        while current <= max_strike
          strikes << current
          current += step
        end
        strikes
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
          @logger.info("[ENTRY] Placed #{signal} order: #{symbol} #{strike_info[:option_type]} #{strike_info[:strike]} @ ₹#{strike_info[:premium].round(2)}")
          :success
        else
          @logger.error("[ENTRY] Failed to place order: #{result[:error]}")
          :order_failed
        end
      end
    end
  end
end
