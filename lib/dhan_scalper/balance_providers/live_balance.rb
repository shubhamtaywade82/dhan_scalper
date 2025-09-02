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

      def update_balance(_amount, type: :debit)
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
        # Use the correct DhanHQ::Models::Funds.fetch method
        puts "[DEBUG] Attempting to fetch funds from DhanHQ API..."
        funds = DhanHQ::Models::Funds.fetch
        puts "[DEBUG] Funds object: #{funds.inspect}"

        if funds.respond_to?(:available_balance)
          # Calculate used balance as difference between total and available
          total = funds.available_balance.to_f
          available = funds.available_balance.to_f
          used = funds.utilized_amount.to_f

          @cache = {
            available: available,
            used: used,
            total: total
          }
        else
          puts "[DEBUG] Funds object doesn't have expected methods, using fallback"
          # Fallback to basic structure if API response is different
          @cache = {
            available: 100_000.0, # Default fallback
            used: 0.0,
            total: 100_000.0
          }
        end

        puts "[DEBUG] Cache updated: #{@cache.inspect}"
        @cache_time = Time.now
      rescue StandardError => e
        puts "Warning: Failed to fetch live balance: #{e.message}"
        puts "Backtrace: #{e.backtrace.first(3).join("\n")}"
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
