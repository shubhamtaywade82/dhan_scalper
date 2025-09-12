# frozen_string_literal: true

require_relative "equity_calculator"

module DhanScalper
  module Services
    # Service to handle MTM refresh in tick loop
    class MtmRefreshService
      def initialize(equity_calculator:, logger: Logger.new($stdout))
        @equity_calculator = equity_calculator
        @logger = logger
        @last_refresh = {}
        @refresh_interval = 1 # seconds
      end

      # Refresh MTM for a specific security when tick is received
      def on_tick_received(exchange_segment:, security_id:, ltp:)
        # Check if we have a position for this security
        position = @equity_calculator.instance_variable_get(:@position_tracker).get_position(
          exchange_segment: exchange_segment,
          security_id: security_id,
          side: "LONG",
        )

        return unless position && DhanScalper::Support::Money.positive?(position[:net_qty])

        # Rate limit refreshes to avoid excessive updates
        key = "#{exchange_segment}_#{security_id}"
        now = Time.now.to_f

        return if @last_refresh[key] && (now - @last_refresh[key]) < @refresh_interval

        @last_refresh[key] = now

        # Update current price in position first
        @equity_calculator.instance_variable_get(:@position_tracker).update_current_price(
          exchange_segment: exchange_segment,
          security_id: security_id,
          side: "LONG",
          current_price: ltp,
        )

        # Refresh unrealized PnL for this position
        result = @equity_calculator.refresh_unrealized!(
          exchange_segment: exchange_segment,
          security_id: security_id,
          current_ltp: ltp,
        )

        return unless result[:success]

        # Log equity update
        equity = @equity_calculator.calculate_equity
        @logger.debug("[TICK] #{security_id} | LTP: ₹#{DhanScalper::Support::Money.dec(ltp)} | Equity: ₹#{DhanScalper::Support::Money.dec(equity[:total_equity])}")
      end

      # Refresh MTM for all positions (useful for batch updates)
      def refresh_all_positions(ltp_provider: nil)
        @equity_calculator.refresh_all_unrealized!(ltp_provider: ltp_provider)
      end

      # Get current equity with detailed breakdown
      def get_current_equity
        @equity_calculator.calculate_equity
      end

      # Get detailed equity breakdown including all positions
      def get_equity_breakdown
        @equity_calculator.get_equity_breakdown
      end

      # Set refresh interval (in seconds)
      def set_refresh_interval(interval_seconds)
        @refresh_interval = interval_seconds
        @logger.info("[MTM] Refresh interval set to #{interval_seconds} seconds")
      end

      # Clear refresh history (useful for testing)
      def clear_refresh_history
        @last_refresh.clear
        @logger.debug("[MTM] Refresh history cleared")
      end
    end
  end
end
