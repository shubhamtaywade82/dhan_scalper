# frozen_string_literal: true

module DhanScalper
  module Brokers
    class DhanBroker < Base
      def initialize(virtual_data_manager: nil, balance_provider: nil, logger: Logger.new($stdout))
        super(virtual_data_manager: virtual_data_manager)
        @balance_provider = balance_provider
        @logger = logger
      end

      # Unified place_order for compatibility with services/order_manager
      def place_order(symbol:, instrument_id:, side:, quantity:, price:, order_type: "MARKET")
        segment = "NSE_FO" # default to options segment; adjust if instrument metadata available
        case side.to_s.upcase
        when "BUY"
          order = buy_market(segment: segment, security_id: instrument_id, quantity: quantity)
        else
          order = sell_market(segment: segment, security_id: instrument_id, quantity: quantity)
        end

        {
          success: !order.nil?,
          order_id: order&.id,
          order: order,
          position: nil
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
          quantity: quantity
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
          current_price: price
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
          quantity: quantity
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
          current_price: price
        )
        log_position(position)

        order_obj
      end

      private

      def create_order(params)
        # Try multiple methods to create order
        methods_to_try = [
          -> { create_order_via_models(params) },
          -> { create_order_via_direct(params) },
          -> { create_order_via_orders(params) }
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
          -> { DhanHQ::Trades.find_by_order_id(order_id)&.avg_price }
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
            order_id: order_id
          }
        rescue StandardError => e
          @logger&.error "[DHAN_BROKER] Error fetching order status for #{order_id}: #{e.message}"
          nil
        end
      end
    end
  end
end
