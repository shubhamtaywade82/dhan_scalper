# frozen_string_literal: true

module DhanScalper
  module Brokers
    class PaperBroker < Base
      def initialize(virtual_data_manager: nil, balance_provider: nil, logger: Logger.new($stdout))
        super(virtual_data_manager: virtual_data_manager)
        @balance_provider = balance_provider
        @logger = logger
      end

      def buy_market(segment:, security_id:, quantity:, charge_per_order: 20)
        price = DhanScalper::TickCache.ltp(segment, security_id).to_f
        return nil unless price&.positive?

        # Calculate total cost including charges
        total_cost = (price * quantity) + charge_per_order

        # Check if we can afford this position
        if @balance_provider && @balance_provider.available_balance < total_cost
          @logger.warn("[PAPER] Insufficient balance. Need ₹#{total_cost.round(2)}, have ₹#{@balance_provider.available_balance.round(2)}")
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

        order = Order.new("P-#{Time.now.to_f}", security_id, "SELL", quantity, price)

        # Log the order
        log_order(order)

        # Find and close matching position
        close_matching_position(security_id, quantity, price)

        order
      end

      # Generic place_order method for compatibility with PaperApp
      def place_order(symbol:, instrument_id:, side:, quantity:, price:, order_type: "MARKET")
        order_id = "P-#{Time.now.to_f}"
        order = Order.new(order_id, instrument_id, side, quantity, price)

        # Log the order
        log_order(order)

        case side.upcase
        when "BUY"
          # Calculate total cost including charges
          charge_per_order = 20
          total_cost = (price * quantity) + charge_per_order

          # Check if we can afford this position
          if @balance_provider && @balance_provider.available_balance < total_cost
            return {
              success: false,
              error: "Insufficient balance. Required: ₹#{total_cost.round(2)}, Available: ₹#{@balance_provider.available_balance.round(2)}"
            }
          end

          # Debit the balance (including charges)
          @balance_provider&.update_balance(total_cost, type: :debit)

          # Create and log position
          position = DhanScalper::Position.new(
            security_id: instrument_id,
            side: side,
            entry_price: price,
            quantity: quantity,
            current_price: price
          )
          log_position(position)

          {
            success: true,
            order_id: order_id,
            order: order,
            position: position
          }

        when "SELL"
          # Close matching position
          close_matching_position(instrument_id, quantity, price)

          {
            success: true,
            order_id: order_id,
            order: order,
            position: nil
          }

        else
          {
            success: false,
            error: "Invalid side: #{side}. Use 'BUY' or 'SELL'"
          }
        end
      end

      private

      # Close matching position when selling
      def close_matching_position(security_id, quantity, exit_price)
        positions = @virtual_data_manager.get_positions

        # Find matching position
        matching_position = positions.find do |pos|
          pos[:security_id] == security_id && pos[:quantity] == quantity
        end

        if matching_position
          # Calculate P&L
          entry_price = matching_position[:entry_price]
          pnl = (exit_price - entry_price) * quantity

          # Update balance with P&L
          @balance_provider&.add_realized_pnl(pnl)

          # Remove position
          @virtual_data_manager.remove_position(security_id)

          @logger.info "[PAPER] Position closed: #{security_id} | Entry: ₹#{entry_price} | Exit: ₹#{exit_price} | P&L: ₹#{pnl.round(2)}"
        else
          @logger.warn "[PAPER] No matching position found for #{security_id} (qty: #{quantity})"
        end
      end
    end
  end
end
