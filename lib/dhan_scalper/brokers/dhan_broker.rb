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
          result = method.call
          return result if result && !result[:error]
        rescue StandardError
          next
        end

        { error: "Failed to create order via all available methods" }
      end

      def create_order_via_models(params)
        # Try DhanHQ::Models::Order.new

        puts "[DEBUG] Attempting to create order via DhanHQ::Models::Order.new"
        order = DhanHQ::Models::Order.new(params)
        puts "[DEBUG] Order object created: #{order.inspect}"
        order.save
        puts "[DEBUG] Order save result: persisted=#{order.persisted?}, errors=#{order.errors.full_messages}"
        return { order_id: order.order_id, error: nil } if order.persisted?

        { error: order.errors.full_messages.join(", ") }
      rescue StandardError => e
        puts "[DEBUG] Error in create_order_via_models: #{e.message}"
        { error: e.message }
      end

      def create_order_via_direct(params)
        # Try DhanHQ::Order.new

        puts "[DEBUG] Attempting to create order via DhanHQ::Order.new"
        order = DhanHQ::Order.new(params)
        puts "[DEBUG] Order object created: #{order.inspect}"
        order.save
        puts "[DEBUG] Order save result: persisted=#{order.persisted?}, errors=#{order.errors.full_messages}"
        return { order_id: order.order_id, error: nil } if order.persisted?

        { error: order.errors.full_messages.join(", ") }
      rescue StandardError => e
        puts "[DEBUG] Error in create_order_via_direct: #{e.message}"
        { error: e.message }
      end

      def create_order_via_orders(params)
        # Try DhanHQ::Orders.create

        puts "[DEBUG] Attempting to create order via DhanHQ::Orders.create"
        order = DhanHQ::Orders.create(params)
        puts "[DEBUG] Order object created: #{order.inspect}"
        return { order_id: order.order_id || order.id, error: nil } if order

        { error: "Failed to create order" }
      rescue StandardError => e
        puts "[DEBUG] Error in create_order_via_orders: #{e.message}"
        { error: e.message }
      end

      def fetch_trade_price(order_id)
        puts "[DEBUG] Attempting to fetch trade price for order_id: #{order_id}"
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
          puts "[DEBUG] Trying method #{index + 1} to fetch trade price"
          result = method.call
          puts "[DEBUG] Method #{index + 1} result: #{result.inspect}"
          return result.to_f if result
        rescue StandardError => e
          puts "[DEBUG] Method #{index + 1} failed: #{e.message}"
          next
        end

        puts "[DEBUG] All methods failed to fetch trade price"
        nil
      end
    end
  end
end
