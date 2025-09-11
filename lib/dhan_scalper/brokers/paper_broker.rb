# frozen_string_literal: true

require_relative "../support/money"
require_relative "../services/enhanced_position_tracker"

module DhanScalper
  module Brokers
    class PaperBroker < Base
      def initialize(virtual_data_manager: nil, balance_provider: nil, logger: Logger.new($stdout))
        super(virtual_data_manager: virtual_data_manager)
        @balance_provider = balance_provider
        @logger = logger
        @position_tracker = DhanScalper::Services::EnhancedPositionTracker.new
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

        # Add position to enhanced tracker
        position = @position_tracker.add_position(
          exchange_segment: segment,
          security_id: security_id,
          side: "LONG",
          quantity: quantity,
          price: price,
          fee: charge_per_order
        )

        order = Order.new("P-#{Time.now.to_f}", security_id, "BUY", quantity, price)

        # Log the order
        log_order(order)

        @logger.info("[PAPER] Position added: #{security_id} | Qty: #{DhanScalper::Support::Money.dec(quantity_bd)} @ ₹#{DhanScalper::Support::Money.dec(price_bd)} | Avg: ₹#{DhanScalper::Support::Money.dec(position[:buy_avg])} | Net Qty: #{DhanScalper::Support::Money.dec(position[:net_qty])}")

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

        # Process partial exit through enhanced tracker
        result = @position_tracker.partial_exit(
          exchange_segment: segment,
          security_id: security_id,
          side: "LONG",
          quantity: quantity,
          price: price,
          fee: charge_per_order
        )

        if result
          # Credit net proceeds to balance
          @balance_provider&.update_balance(result[:net_proceeds], type: :credit)

          # Update realized PnL in balance provider
          @balance_provider&.add_realized_pnl(result[:realized_pnl])

          @logger.info("[PAPER] Partial exit: #{security_id} | Sold: #{DhanScalper::Support::Money.dec(result[:sold_quantity])} @ ₹#{DhanScalper::Support::Money.dec(price_bd)} | Realized PnL: ₹#{DhanScalper::Support::Money.dec(result[:realized_pnl])} | Net Proceeds: ₹#{DhanScalper::Support::Money.dec(result[:net_proceeds])} | Remaining: #{DhanScalper::Support::Money.dec(result[:position][:net_qty])}")
        else
          @logger.warn("[PAPER] No position found for partial exit: #{security_id} (qty: #{quantity})")
        end

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
          # Use buy_market method for consistency
          buy_result = buy_market(segment: "NSE_EQ", security_id: instrument_id, quantity: quantity, charge_per_order: 20)

          if buy_result
            position = @position_tracker.get_position(exchange_segment: "NSE_EQ", security_id: instrument_id, side: "LONG")
            {
              success: true,
              order_id: order_id,
              order: order,
              position: position
            }
          else
            {
              success: false,
              error: "Failed to execute buy order"
            }
          end

        when "SELL"
          # Use sell_market method for consistency
          sell_result = sell_market(segment: "NSE_EQ", security_id: instrument_id, quantity: quantity, charge_per_order: 20)

          if sell_result
            position = @position_tracker.get_position(exchange_segment: "NSE_EQ", security_id: instrument_id, side: "LONG")
            {
              success: true,
              order_id: order_id,
              order: order,
              position: position
            }
          else
            {
              success: false,
              error: "Failed to execute sell order"
            }
          end

        else
          {
            success: false,
            error: "Invalid side: #{side}. Use 'BUY' or 'SELL'"
          }
        end
      end

      # Get position tracker for external access
      def position_tracker
        @position_tracker
      end

      # Get balance provider for external access
      def balance_provider
        @balance_provider
      end

      # Place order with idempotency support
      def place_order!(symbol:, instrument_id:, side:, quantity:, price:, order_type: "MARKET", idempotency_key: nil, redis_store: nil)
        # Check for existing order if idempotency key is provided
        if idempotency_key && redis_store
          existing_order_id = redis_store.get_idempotency_key(idempotency_key)
          if existing_order_id
            @logger.info("[PAPER] Idempotency key found: #{idempotency_key} -> #{existing_order_id}, returning existing order")

            # Get the existing order from virtual data manager
            existing_order = @virtual_data_manager&.get_order_by_id(existing_order_id)
            if existing_order
              return {
                success: true,
                order_id: existing_order_id,
                order: existing_order,
                position: get_position_for_order(existing_order),
                idempotent: true
              }
            else
              @logger.warn("[PAPER] Idempotency key found but order not found: #{idempotency_key} -> #{existing_order_id}")
            end
          end
        end

        # Place the order normally
        result = place_order(
          symbol: symbol,
          instrument_id: instrument_id,
          side: side,
          quantity: quantity,
          price: price,
          order_type: order_type
        )

        # Store idempotency key if provided and order was successful
        if result[:success] && idempotency_key && redis_store
          redis_store.store_idempotency_key(idempotency_key, result[:order_id])
          @logger.info("[PAPER] Stored idempotency key: #{idempotency_key} -> #{result[:order_id]}")
        end

        result
      end

      private

      # Get position for an existing order
      def get_position_for_order(order)
        return nil unless order

        # Try to get position from enhanced tracker
        position = @position_tracker.get_position(
          exchange_segment: "NSE_EQ",
          security_id: order[:security_id] || order["security_id"],
          side: "LONG"
        )

        position
      end
    end
  end
end
