# frozen_string_literal: true

require_relative "../support/money"

module DhanScalper
  module Brokers
    class PaperBroker < Base
      def initialize(virtual_data_manager: nil, balance_provider: nil, logger: Logger.new($stdout))
        super(virtual_data_manager: virtual_data_manager)
        @balance_provider = balance_provider
        @logger = logger
      end

      def buy_market(segment:, security_id:, quantity:, charge_per_order: 20)
        price = DhanScalper::TickCache.ltp(segment, security_id)
        return nil unless price&.positive?

        # Convert to BigDecimal for safe money calculations
        price_bd = DhanScalper::Support::Money.bd(price)
        quantity_bd = DhanScalper::Support::Money.bd(quantity)
        charge_bd = DhanScalper::Support::Money.bd(charge_per_order)

        # Calculate total cost including charges: (price * quantity) + fee
        total_cost = DhanScalper::Support::Money.add(
          DhanScalper::Support::Money.multiply(price_bd, quantity_bd),
          charge_bd
        )

        # Check if we can afford this position
        if @balance_provider && @balance_provider.available_balance < total_cost
          @logger.warn("[PAPER] Insufficient balance. Need ₹#{DhanScalper::Support::Money.dec(total_cost)}, have ₹#{DhanScalper::Support::Money.dec(@balance_provider.available_balance)}")
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
        price = DhanScalper::TickCache.ltp(segment, security_id)
        return nil unless price&.positive?

        # Convert to BigDecimal for safe money calculations
        price_bd = DhanScalper::Support::Money.bd(price)
        quantity_bd = DhanScalper::Support::Money.bd(quantity)
        charge_bd = DhanScalper::Support::Money.bd(charge_per_order)

        order = Order.new("P-#{Time.now.to_f}", security_id, "SELL", quantity, price)

        # Log the order
        log_order(order)

        # Find and close matching position
        close_matching_position(security_id, quantity, price_bd, charge_bd)

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
          # Convert to BigDecimal for safe money calculations
          price_bd = DhanScalper::Support::Money.bd(price)
          quantity_bd = DhanScalper::Support::Money.bd(quantity)
          charge_bd = DhanScalper::Support::Money.bd(20)

          # Calculate total cost including charges: (price * quantity) + fee
          total_cost = DhanScalper::Support::Money.add(
            DhanScalper::Support::Money.multiply(price_bd, quantity_bd),
            charge_bd
          )

          # Check if we can afford this position
          if @balance_provider && @balance_provider.available_balance < total_cost
            return {
              success: false,
              error: "Insufficient balance. Required: ₹#{DhanScalper::Support::Money.dec(total_cost)}, Available: ₹#{DhanScalper::Support::Money.dec(@balance_provider.available_balance)}"
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
          # Convert to BigDecimal for safe money calculations
          price_bd = DhanScalper::Support::Money.bd(price)
          charge_bd = DhanScalper::Support::Money.bd(20)

          # Close matching position
          close_matching_position(instrument_id, quantity, price_bd, charge_bd)

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
      def close_matching_position(security_id, quantity, exit_price_bd, charge_bd)
        positions = @virtual_data_manager.get_positions

        # Find matching position
        matching_position = positions.find do |pos|
          pos[:security_id] == security_id && pos[:quantity] == quantity
        end

        if matching_position
          # Convert entry price to BigDecimal
          entry_price_bd = DhanScalper::Support::Money.bd(matching_position[:entry_price])
          quantity_bd = DhanScalper::Support::Money.bd(quantity)

          # Calculate gross proceeds: exit_price * quantity
          gross_proceeds = DhanScalper::Support::Money.multiply(exit_price_bd, quantity_bd)

          # Calculate net proceeds: gross_proceeds - fee
          net_proceeds = DhanScalper::Support::Money.subtract(gross_proceeds, charge_bd)

          # Calculate realized P&L: (exit_price - entry_price) * quantity
          realized_pnl = DhanScalper::Support::Money.multiply(
            DhanScalper::Support::Money.subtract(exit_price_bd, entry_price_bd),
            quantity_bd
          )

          # Credit net proceeds to balance (full proceeds minus fees)
          @balance_provider&.update_balance(net_proceeds, type: :credit)

          # Track realized P&L separately (for reporting only)
          @balance_provider&.add_realized_pnl(realized_pnl)

          # Remove position
          @virtual_data_manager.remove_position(security_id)

          @logger.info "[PAPER] Position closed: #{security_id} | Entry: ₹#{DhanScalper::Support::Money.dec(entry_price_bd)} | Exit: ₹#{DhanScalper::Support::Money.dec(exit_price_bd)} | Net Proceeds: ₹#{DhanScalper::Support::Money.dec(net_proceeds)} | Realized P&L: ₹#{DhanScalper::Support::Money.dec(realized_pnl)}"
        else
          @logger.warn "[PAPER] No matching position found for #{security_id} (qty: #{quantity})"
        end
      end
    end
  end
end
