# frozen_string_literal: true

module DhanScalper
  module Brokers
    class PaperBroker < Base
      def initialize(virtual_data_manager: nil, balance_provider: nil)
        super(virtual_data_manager: virtual_data_manager)
        @balance_provider = balance_provider
      end

      def buy_market(segment:, security_id:, quantity:, charge_per_order: 20)
        price = DhanScalper::TickCache.ltp(segment, security_id).to_f
        return nil unless price&.positive?

        # Calculate total cost including charges
        total_cost = (price * quantity) + charge_per_order

        # Check if we can afford this position
        if @balance_provider && @balance_provider.available_balance < total_cost
          puts "Warning: Insufficient balance for paper trade. Required: ₹#{total_cost.round(2)}, Available: ₹#{@balance_provider.available_balance.round(2)}"
          return nil
        end

        # Debit the balance (including charges)
        @balance_provider&.update_balance(total_cost, type: :debit)

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

      def sell_market(segment:, security_id:, quantity:, charge_per_order: 20)
        price = DhanScalper::TickCache.ltp(segment, security_id).to_f
        return nil unless price&.positive?

        # For paper trading, we don't update balance here
        # The balance update is handled by the trader's close! method
        # which calculates the net P&L and updates the balance accordingly

        order = Order.new("P-#{Time.now.to_f}", security_id, "SELL", quantity, price)

        # Log the order
        log_order(order)

        # For sell orders (position exits), we don't create a new position
        # The position management is handled by the trader's close! method
        # which will remove the existing position from the virtual data manager

        order
      end
    end
  end
end
