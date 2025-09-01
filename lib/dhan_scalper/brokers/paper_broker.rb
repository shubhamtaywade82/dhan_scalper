# frozen_string_literal: true

module DhanScalper
  module Brokers
    class PaperBroker < Base
      def buy_market(segment:, security_id:, quantity:)
        price = DhanScalper::TickCache.ltp(segment, security_id).to_f
        order = Order.new("P-#{Time.now.to_f}", security_id, "BUY", quantity, price)

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
        price = DhanScalper::TickCache.ltp(segment, security_id).to_f
        order = Order.new("P-#{Time.now.to_f}", security_id, "SELL", quantity, price)

        # Log the order and create a virtual position
        log_order(order)

        # Create and log position
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
