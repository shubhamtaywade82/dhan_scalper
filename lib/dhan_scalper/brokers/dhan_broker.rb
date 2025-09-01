# frozen_string_literal: true

module DhanScalper
  module Brokers
    class DhanBroker < Base
      def initialize(virtual_data_manager: nil, balance_provider: nil)
        super(virtual_data_manager: virtual_data_manager)
        @balance_provider = balance_provider
      end

      def buy_market(segment:, security_id:, quantity:)
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

      def sell_market(segment:, security_id:, quantity:)
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
          begin
            result = method.call
            return result if result && !result[:error]
          rescue StandardError => e
            next
          end
        end

        { error: "Failed to create order via all available methods" }
      end

      def create_order_via_models(params)
        # Try DhanHQ::Models::Order.new
        begin
          order = DhanHQ::Models::Order.new(params)
          order.save
          return { order_id: order.order_id, error: nil } if order.persisted?
          return { error: order.errors.full_messages.join(", ") }
        rescue StandardError => e
          return { error: e.message }
        end
      end

      def create_order_via_direct(params)
        # Try DhanHQ::Order.new
        begin
          order = DhanHQ::Order.new(params)
          order.save
          return { order_id: order.order_id, error: nil } if order.persisted?
          return { error: order.errors.full_messages.join(", ") }
        rescue StandardError => e
          return { error: e.message }
        end
      end

      def create_order_via_orders(params)
        # Try DhanHQ::Orders.create
        begin
          order = DhanHQ::Orders.create(params)
          return { order_id: order.order_id || order.id, error: nil } if order
          return { error: "Failed to create order" }
        rescue StandardError => e
          return { error: e.message }
        end
      end

      def fetch_trade_price(order_id)
        # Try multiple methods to fetch trade price
        methods_to_try = [
          -> { DhanHQ::Models::Trade.find_by_order_id(order_id)&.avg_price },
          -> { DhanHQ::Trade.find_by_order_id(order_id)&.avg_price },
          -> { DhanHQ::Models::Trade.find_by(order_id: order_id)&.avg_price },
          -> { DhanHQ::Trade.find_by(order_id: order_id)&.avg_price },
          -> { DhanHQ::Models::Trades.find_by_order_id(order_id)&.avg_price },
          -> { DhanHQ::Trades.find_by_order_id(order_id)&.avg_price }
        ]

        methods_to_try.each do |method|
          begin
            result = method.call
            return result.to_f if result
          rescue StandardError
            next
          end
        end

        nil
      end
    end
  end
end
