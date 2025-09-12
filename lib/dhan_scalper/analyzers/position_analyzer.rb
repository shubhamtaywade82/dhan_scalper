# frozen_string_literal: true

require_relative "../support/application_service"

module DhanScalper
  module Analyzers
    # Position analyzer for computing P&L, peak tracking, and trigger calculations
    class PositionAnalyzer < DhanScalper::ApplicationService
      attr_reader :cache, :tick_cache

      def initialize(cache:, tick_cache:)
        @cache = cache
        @tick_cache = tick_cache
      end

      def call(position)
        return nil unless position&.dig(:security_id)

        security_id = position[:security_id]
        entry_price = position[:entry_price]&.to_f
        quantity = position[:quantity]&.to_i
        lot_size = position[:lot_size]&.to_i || 75

        return nil unless entry_price&.positive? && quantity&.positive?

        # Get current price from tick cache
        current_price = get_current_price(security_id)
        return nil unless current_price&.positive?

        # Calculate P&L
        pnl = calculate_pnl(entry_price, current_price, quantity, lot_size)
        pnl_pct = calculate_pnl_percentage(entry_price, current_price)

        # Update peak price atomically
        peak_price = update_peak_price(security_id, current_price, entry_price)

        # Calculate peak percentage
        peak_pct = calculate_peak_percentage(entry_price, peak_price)

        {
          security_id: security_id,
          entry_price: entry_price,
          current_price: current_price,
          quantity: quantity,
          lot_size: lot_size,
          pnl: pnl,
          pnl_pct: pnl_pct,
          peak_price: peak_price,
          peak_pct: peak_pct,
          timestamp: Time.now,
        }
      end

      private

      def get_current_price(security_id)
        # Try different segments to find the price
        segments = %w[NSE_FNO IDX_I NSE_EQ BSE_EQ]

        segments.each do |segment|
          price = @tick_cache.ltp(segment, security_id)
          return price if price&.positive?
        end

        nil
      end

      def calculate_pnl(entry_price, current_price, quantity, lot_size)
        # For options, P&L calculation depends on position side
        # This is a simplified calculation - in reality, you'd need to know if it's CE/PE
        (current_price - entry_price) * quantity * lot_size
      end

      def calculate_pnl_percentage(entry_price, current_price)
        return 0.0 if entry_price.zero?

        ((current_price - entry_price) / entry_price) * 100
      end

      def update_peak_price(security_id, current_price, entry_price)
        peak_key = "peak:#{security_id}"

        # Get current peak price
        current_peak = @cache.get(peak_key)&.to_f || entry_price

        # Only update if current price is higher (for long positions)
        if current_price > current_peak
          @cache.set(peak_key, current_price.to_s, ttl: 3_600) # 1 hour TTL
          current_price
        else
          current_peak
        end
      end

      def calculate_peak_percentage(entry_price, peak_price)
        return 0.0 if entry_price.zero?

        ((peak_price - entry_price) / entry_price) * 100
      end
    end
  end
end
