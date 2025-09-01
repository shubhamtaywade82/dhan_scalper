# frozen_string_literal: true

module DhanScalper
  module Brokers
    class DhanBroker < Base
      def initialize(virtual_data_manager: nil, balance_provider: nil)
        super(virtual_data_manager: virtual_data_manager)
        @balance_provider = balance_provider
      end

      def buy_market(segment:, security_id:, quantity:)
        o = DhanHQ::Models::Order.new(transaction_type: "BUY", exchange_segment: segment,
                                      product_type: "MARGIN", order_type: "MARKET", validity: "DAY", security_id: security_id, quantity: quantity)

        o.save
        raise o.errors.full_messages.join(", ") unless o.persisted?

        # try best-effort trade price
        price = begin
          DhanHQ::Models::Trade.find_by_order_id(o.order_id)&.avg_price
        rescue StandardError
          nil
        end || 0.0

        order = Order.new(o.order_id, security_id, "BUY", quantity, price)

        # Log the order and create a virtual position
        log_order(order)

        # Create and log position
        position = DhanScalper::Position.new(
          security_id: security_id,
          side: "BUY",
          entry_price: price,
          quantity: quantity,
          current_price: price
        )
        log_position(position)

        order
      end

      def sell_market(segment:, security_id:, quantity:)
        o = DhanHQ::Models::Order.new(transaction_type: "SELL", exchange_segment: segment,
                                      product_type: "MARGIN", order_type: "MARKET", validity: "DAY", security_id: security_id, quantity: quantity)

        o.save
        raise o.errors.full_messages.join(", ") unless o.persisted?

        price = begin
          DhanHQ::Models::Trade.find_by_order_id(o.order_id)&.avg_price
        rescue StandardError
          nil
        end || 0.0

        order = Order.new(o.order_id, security_id, "SELL", quantity, price)

        # Log the order and create a virtual position
        log_order(order)

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

        order
      end
    end
  end
end
