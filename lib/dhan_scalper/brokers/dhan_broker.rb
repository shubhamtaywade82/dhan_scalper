# frozen_string_literal: true

module DhanScalper
  module Brokers
    class DhanBroker < Base
      def initialize(virtual_data_manager: nil, balance_provider: nil, logger: Logger.new($stdout))
        super(virtual_data_manager: virtual_data_manager)
        @balance_provider = balance_provider
        @logger = logger
        @order_cache = {}
        @position_cache = {}
        @last_sync = Time.now
        @sync_interval = 30 # seconds
      end

      # Unified place_order for compatibility with services/order_manager
      def place_order(symbol:, instrument_id:, side:, quantity:, price:, order_type: "MARKET")
        segment = "NSE_FO" # default to options segment; adjust if instrument metadata available
        order = case side.to_s.upcase
                when "BUY"
                  buy_market(segment: segment, security_id: instrument_id, quantity: quantity)
                else
                  sell_market(segment: segment, security_id: instrument_id, quantity: quantity)
                end

        {
          success: !order.nil?,
          order_id: order&.id,
          order: order,
          position: nil,
        }
      rescue StandardError => e
        { success: false, error: e.message }
      end

      def buy_market(segment:, security_id:, quantity:, charge_per_order: nil)
        order_params = {
          transaction_type: "BUY",
          exchange_segment: segment,
          product_type: "MARGIN",
          order_type: "MARKET",
          validity: "DAY",
          security_id: security_id,
          quantity: quantity,
        }

        order = create_order(order_params)
        raise order[:error] if order[:error]

        # try best-effort trade price
        price = fetch_trade_price(order[:order_id]) || 0.0

        order_obj = Order.new(order[:order_id], security_id, "BUY", quantity, price)

        # Log the order and create a virtual position
        log_order(order_obj)

        # Create and log position
        position = DhanScalper::Position.new(
          security_id: security_id,
          side: "BUY",
          entry_price: price,
          quantity: quantity,
          current_price: price,
        )
        log_position(position)

        order_obj
      end

      def sell_market(segment:, security_id:, quantity:, charge_per_order: nil)
        order_params = {
          transaction_type: "SELL",
          exchange_segment: segment,
          product_type: "MARGIN",
          order_type: "MARKET",
          validity: "DAY",
          security_id: security_id,
          quantity: quantity,
        }

        order = create_order(order_params)
        raise order[:error] if order[:error]

        price = fetch_trade_price(order[:order_id]) || 0.0

        order_obj = Order.new(order[:order_id], security_id, "SELL", quantity, price)

        # Log the order and create a virtual position
        log_order(order_obj)

        # Create and log position
        require_relative "../position"
        position = DhanScalper::Position.new(
          security_id: security_id,
          side: "SELL",
          entry_price: price,
          quantity: quantity,
          current_price: price,
        )
        log_position(position)

        order_obj
      end

      # Enhanced live trading methods
      def get_positions
        sync_positions_if_needed
        @position_cache.values
      end

      def get_orders(status: nil)
        sync_orders_if_needed
        orders = @order_cache.values
        return orders unless status

        orders.select { |order| order[:status] == status }
      end

      def cancel_order(order_id)
        result = DhanHQ::Order.cancel_order(order_id)
        if result && result["success"]
          @logger.info "[DHAN_BROKER] Order #{order_id} cancelled successfully"
          @order_cache.delete(order_id)
          true
        else
          @logger.error "[DHAN_BROKER] Failed to cancel order #{order_id}: #{result&.dig("message")}"
          false
        end
      rescue StandardError => e
        @logger.error "[DHAN_BROKER] Error cancelling order #{order_id}: #{e.message}"
        false
      end

      def get_funds
        funds = DhanHQ::Models::Funds.fetch
        return nil unless funds

        {
          available_balance: funds.available_balance.to_f,
          utilized_amount: funds.utilized_amount.to_f,
          total_balance: (funds.available_balance.to_f + funds.utilized_amount.to_f),
          timestamp: Time.now,
        }
      rescue StandardError => e
        @logger.error "[DHAN_BROKER] Error fetching funds: #{e.message}"
        nil
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
            pnl_percentage: holding.pnl_percentage.to_f,
          }
        end
      rescue StandardError => e
        @logger.error "[DHAN_BROKER] Error fetching holdings: #{e.message}"
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
            timestamp: trade.timestamp,
          }
        end
      rescue StandardError => e
        @logger.error "[DHAN_BROKER] Error fetching trades: #{e.message}"
        []
      end

      def get_order_status(order_id)
        return nil unless order_id

        begin
          # Get order details from DhanHQ
          order_details = DhanHQ::Order.get_order_details(order_id)
          return nil unless order_details&.dig("data")

          order_data = order_details["data"]
          {
            status: order_data["orderStatus"],
            fill_price: order_data["averagePrice"],
            fill_quantity: order_data["filledQuantity"],
            reason: order_data["rejectionReason"],
            order_id: order_id,
          }
        rescue StandardError => e
          @logger&.error "[DHAN_BROKER] Error fetching order status for #{order_id}: #{e.message}"
          nil
        end
      end

      private

      def create_order(params)
        # Try multiple methods to create order
        methods_to_try = [
          -> { create_order_via_models(params) },
          -> { create_order_via_direct(params) },
          -> { create_order_via_orders(params) },
        ]

        methods_to_try.each do |method|
          result = method.call
          return result if result && !result[:error]
        rescue StandardError
          next
        end

        { error: "Failed to create order via all available methods" }
      end

      def create_order_via_models(params)
        # Try DhanHQ::Models::Order.new

        @logger.debug "[DHAN] Attempting create via DhanHQ::Models::Order.new"
        order = DhanHQ::Models::Order.new(params)
        @logger.debug "[DHAN] Order object: #{order.inspect}"
        order.save
        @logger.debug "[DHAN] Save: persisted=#{order.persisted?} errors=#{order.errors.full_messages}"
        return { order_id: order.order_id, error: nil } if order.persisted?

        { error: order.errors.full_messages.join(", ") }
      rescue StandardError => e
        @logger.debug "[DHAN] create_order_via_models error: #{e.message}"
        { error: e.message }
      end

      def create_order_via_direct(params)
        # Try DhanHQ::Order.new

        @logger.debug "[DHAN] Attempting create via DhanHQ::Order.new"
        order = DhanHQ::Order.new(params)
        @logger.debug "[DHAN] Order object: #{order.inspect}"
        order.save
        @logger.debug "[DHAN] Save: persisted=#{order.persisted?} errors=#{order.errors.full_messages}"
        return { order_id: order.order_id, error: nil } if order.persisted?

        { error: order.errors.full_messages.join(", ") }
      rescue StandardError => e
        @logger.debug "[DHAN] create_order_via_direct error: #{e.message}"
        { error: e.message }
      end

      def create_order_via_orders(params)
        # Try DhanHQ::Orders.create

        @logger.debug "[DHAN] Attempting create via DhanHQ::Orders.create"
        order = DhanHQ::Orders.create(params)
        @logger.debug "[DHAN] Order response: #{order.inspect}"
        return { order_id: order.order_id || order.id, error: nil } if order

        { error: "Failed to create order" }
      rescue StandardError => e
        @logger.debug "[DHAN] create_order_via_orders error: #{e.message}"
        { error: e.message }
      end

      def fetch_trade_price(order_id)
        @logger.debug "[DHAN] Fetch trade price for order_id=#{order_id}"
        # Try multiple methods to fetch trade price
        methods_to_try = [
          -> { DhanHQ::Models::Trade.find_by_order_id(order_id)&.avg_price },
          -> { DhanHQ::Trade.find_by_order_id(order_id)&.avg_price },
          -> { DhanHQ::Models::Trade.find_by(order_id: order_id)&.avg_price },
          -> { DhanHQ::Trade.find_by(order_id: order_id)&.avg_price },
          -> { DhanHQ::Models::Trades.find_by_order_id(order_id)&.avg_price },
          -> { DhanHQ::Trades.find_by_order_id(order_id)&.avg_price },
        ]

        methods_to_try.each_with_index do |method, index|
          @logger.debug "[DHAN] Price method #{index + 1}"
          result = method.call
          @logger.debug "[DHAN] Price result: #{result.inspect}"
          return result.to_f if result
        rescue StandardError => e
          @logger.debug "[DHAN] Price method error: #{e.message}"
          next
        end

        @logger.debug "[DHAN] All price methods failed"
        nil
      end

      def sync_positions_if_needed
        return if Time.now - @last_sync < @sync_interval

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
              last_updated: Time.now,
            }
          end

          @last_sync = Time.now
          @logger.debug "[DHAN_BROKER] Synced #{@position_cache.size} positions"
        rescue StandardError => e
          @logger.error "[DHAN_BROKER] Error syncing positions: #{e.message}"
        end
      end

      def sync_orders_if_needed
        return if Time.now - @last_sync < @sync_interval

        begin
          orders = DhanHQ::Models::Order.all
          return unless orders

          @order_cache = {}
          orders.each do |order|
            @order_cache[order.order_id] = {
              order_id: order.order_id,
              security_id: order.security_id,
              symbol: order.symbol,
              side: order.transaction_type,
              quantity: order.quantity.to_i,
              price: order.price.to_f,
              status: order.order_status,
              order_type: order.order_type,
              created_at: order.created_at,
              last_updated: Time.now,
            }
          end

          @last_sync = Time.now
          @logger.debug "[DHAN_BROKER] Synced #{@order_cache.size} orders"
        rescue StandardError => e
          @logger.error "[DHAN_BROKER] Error syncing orders: #{e.message}"
        end
      end
    end
  end
end
