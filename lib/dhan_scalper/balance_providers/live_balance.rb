# frozen_string_literal: true

require_relative "base"

module DhanScalper
  module BalanceProviders
    class LiveBalance < Base
      def initialize
        @cache = {}
        @cache_time = nil
        @cache_ttl = 30 # seconds
      end

      def available_balance
        refresh_cache_if_needed
        @cache[:available] || 0.0
      end

      def total_balance
        refresh_cache_if_needed
        @cache[:total] || 0.0
      end

      def used_balance
        refresh_cache_if_needed
        @cache[:used] || 0.0
      end

      def update_balance(amount, type: :debit)
        # For live trading, we don't manually update balance
        # It gets updated via API calls
        refresh_cache
        @cache[:total] || 0.0
      end

      private

      def refresh_cache_if_needed
        return if @cache_time && (Time.now - @cache_time) < @cache_ttl

        refresh_cache
      end

      def refresh_cache
        begin
          # Fetch funds from DhanHQ API
          funds = DhanHQ::Models::Funds.fetch

          if funds && funds.respond_to?(:available_balance)
            @cache = {
              available: funds.available_balance.to_f,
              used: funds.used_margin.to_f,
              total: funds.total_balance.to_f
            }
          else
            # Fallback to basic structure if API response is different
            @cache = {
              available: 100_000.0, # Default fallback
              used: 0.0,
              total: 100_000.0
            }
          end

          @cache_time = Time.now
        rescue StandardError => e
          puts "Warning: Failed to fetch live balance: #{e.message}"
          # Keep existing cache if available, otherwise use defaults
          unless @cache_time
            @cache = {
              available: 100_000.0,
              used: 0.0,
              total: 100_000.0
            }
          end
        end
      end
    end
  end
end
