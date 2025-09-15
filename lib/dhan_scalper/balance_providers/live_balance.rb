# frozen_string_literal: true

require_relative 'base'

module DhanScalper
  module BalanceProviders
    class LiveBalance < Base
      def initialize(logger: Logger.new($stdout))
        @cache = {}
        @cache_time = nil
        @cache_ttl = 30 # seconds
        @logger = logger
        @position_cache = {}
        @last_position_sync = Time.now
        @position_sync_interval = 60 # seconds
      end

      def available_balance
        refresh_cache_if_needed
        (@cache[:available] || 0.0).to_f
      end

      def total_balance
        refresh_cache_if_needed
        (@cache[:total] || 0.0).to_f
      end

      def used_balance
        refresh_cache_if_needed
        (@cache[:used] || 0.0).to_f
      end

      def update_balance(_amount, type: :debit)
        # For live trading, we don't manually update balance
        # It gets updated via API calls
        refresh_cache
        @cache[:total] || 0.0
      end

      # For live trading, realized PnL is reflected by broker/account; we expose
      # a no-op so callers don't error when invoking this hook.
      def add_realized_pnl(_pnl)
        refresh_cache
        @cache[:total] || 0.0
      end

      # Enhanced live trading methods
      def get_positions
        sync_positions_if_needed
        @position_cache.values
      end

      def get_position(security_id)
        sync_positions_if_needed
        @position_cache[security_id]
      end

      def get_funds
        refresh_cache_if_needed
        @cache.merge(timestamp: @cache_time)
      end

      def get_holdings
        holdings = DhanHQ::Models::Holding.all
        return [] unless holdings

        holdings.map do |holding|
          {
            security_id: holding.security_id,
            symbol: holding.symbol,
            quantity: holding.quantity.to_i,
            average_price: holding.average_price.to_f,
            current_price: holding.current_price.to_f,
            pnl: holding.pnl.to_f,
            pnl_percentage: holding.pnl_percentage.to_f
          }
        end
      rescue StandardError => e
        @logger.error "[LIVE_BALANCE] Error fetching holdings: #{e.message}"
        []
      end

      def get_trades(order_id: nil, from_date: nil, to_date: nil)
        trades = DhanHQ::Models::Trade.all
        return [] unless trades

        # Filter by order_id if provided
        trades = trades.select { |t| t.order_id == order_id } if order_id

        # Filter by date range if provided
        if from_date || to_date
          trades = trades.select do |t|
            trade_date = begin
              Time.parse(t.trade_date)
            rescue StandardError
              Time.now
            end
            (from_date.nil? || trade_date >= from_date) &&
              (to_date.nil? || trade_date <= to_date)
          end
        end

        trades.map do |trade|
          {
            trade_id: trade.trade_id,
            order_id: trade.order_id,
            security_id: trade.security_id,
            quantity: trade.quantity.to_i,
            price: trade.price.to_f,
            trade_date: trade.trade_date,
            timestamp: trade.timestamp
          }
        end
      rescue StandardError => e
        @logger.error "[LIVE_BALANCE] Error fetching trades: #{e.message}"
        []
      end

      def get_orders(status: nil)
        orders = DhanHQ::Models::Order.all
        return [] unless orders

        orders = orders.select { |order| order.order_status == status } if status

        orders.map do |order|
          {
            order_id: order.order_id,
            security_id: order.security_id,
            symbol: order.symbol,
            side: order.transaction_type,
            quantity: order.quantity.to_i,
            price: order.price.to_f,
            status: order.order_status,
            order_type: order.order_type,
            created_at: order.created_at
          }
        end
      rescue StandardError => e
        @logger.error "[LIVE_BALANCE] Error fetching orders: #{e.message}"
        []
      end

      private

      def refresh_cache_if_needed
        return if @cache_time && (Time.now - @cache_time) < @cache_ttl

        refresh_cache
      end

      def refresh_cache
        # Use the DhanHQ Funds API and compute balances sanely
        @logger.debug '[LIVE_BALANCE] Attempting to fetch funds from DhanHQ API...'
        funds = DhanHQ::Models::Funds.fetch
        @logger.debug "[LIVE_BALANCE] Funds object: #{funds.inspect}"

        if funds.respond_to?(:available_balance)
          available = funds.available_balance.to_f
          used = funds.respond_to?(:utilized_amount) ? funds.utilized_amount.to_f : 0.0
          total = available + used

          @cache = { available: available, used: used, total: total }
        else
          @logger.warn "[LIVE_BALANCE] Funds object doesn't have expected methods, using fallback"
          @cache = { available: 100_000.0, used: 0.0, total: 100_000.0 }
        end

        @logger.debug "[LIVE_BALANCE] Cache updated: #{@cache.inspect}"
        @cache_time = Time.now
      rescue StandardError => e
        @logger.error "[LIVE_BALANCE] Failed to fetch live balance: #{e.message}"
        @logger.debug "[LIVE_BALANCE] Backtrace: #{e.backtrace.first(3).join("\n")}"
        # Keep existing cache if available, otherwise use defaults
        @cache = { available: 100_000.0, used: 0.0, total: 100_000.0 } unless @cache_time
      end

      def sync_positions_if_needed
        return if Time.now - @last_position_sync < @position_sync_interval

        begin
          positions = DhanHQ::Models::Position.all
          return unless positions

          @position_cache = {}
          positions.each do |pos|
            @position_cache[pos.security_id] = {
              security_id: pos.security_id,
              symbol: pos.symbol,
              quantity: pos.quantity.to_i,
              average_price: pos.average_price.to_f,
              current_price: pos.current_price.to_f,
              pnl: pos.pnl.to_f,
              pnl_percentage: pos.pnl_percentage.to_f,
              last_updated: Time.now
            }
          end

          @last_position_sync = Time.now
          @logger.debug "[LIVE_BALANCE] Synced #{@position_cache.size} positions"
        rescue StandardError => e
          @logger.error "[LIVE_BALANCE] Error syncing positions: #{e.message}"
        end
      end
    end
  end
end
