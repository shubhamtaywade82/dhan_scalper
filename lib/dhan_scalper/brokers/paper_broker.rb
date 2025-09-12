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

      def buy_market(segment:, security_id:, quantity:, charge_per_order: nil)
        puts "Buying market: #{segment}, #{security_id}, #{quantity}, #{charge_per_order}"
        price = DhanScalper::TickCache.ltp(segment, security_id)
        unless price&.positive?
          return create_validation_error("INVALID_PRICE", "No valid price available for #{security_id}")
        end

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
          error_msg = "Insufficient balance. Need ₹#{DhanScalper::Support::Money.dec(total_cost)}, have ₹#{DhanScalper::Support::Money.dec(@balance_provider.available_balance)}"
          @logger.warn("[PAPER] #{error_msg}")
          return create_validation_error("INSUFFICIENT_BALANCE", error_msg)
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
        unless price&.positive?
          return create_validation_error("INVALID_PRICE", "No valid price available for #{security_id}")
        end

        # Convert to BigDecimal for safe money calculations
        price_bd = DhanScalper::Support::Money.bd(price)
        quantity_bd = DhanScalper::Support::Money.bd(quantity)
        charge_bd = DhanScalper::Support::Money.bd(charge_per_order)

        # Check if we have sufficient position to sell
        position = @position_tracker.get_position(
          exchange_segment: segment,
          security_id: security_id,
          side: "LONG"
        )

        unless position && position[:net_qty] && DhanScalper::Support::Money.greater_than_or_equal?(position[:net_qty], quantity_bd)
          available_qty = position&.dig(:net_qty) || 0
          error_msg = "Insufficient position. Trying to sell #{DhanScalper::Support::Money.dec(quantity_bd)}, have #{DhanScalper::Support::Money.dec(available_qty)}"
          @logger.warn("[PAPER] #{error_msg}")
          return create_validation_error("INSUFFICIENT_POSITION", error_msg)
        end

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

          # If position is completely closed, we need to debit the remaining used balance
          if result[:position].nil? || DhanScalper::Support::Money.zero?(result[:position][:net_qty])
            # Calculate the original cost that was used to open this position
            original_buy_cost = DhanScalper::Support::Money.add(
              DhanScalper::Support::Money.multiply(
                result[:position][:buy_qty] || DhanScalper::Support::Money.bd(quantity),
                result[:position][:buy_avg] || DhanScalper::Support::Money.bd(price)
              ),
              DhanScalper::Support::Money.bd(charge_per_order)
            )

            # The net proceeds have already been credited, now we need to debit the difference
            # between original cost and net proceeds to clear the used balance
            remaining_used = DhanScalper::Support::Money.subtract(original_buy_cost, result[:net_proceeds])
            @balance_provider&.update_balance(remaining_used, type: :debit)
          end

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

          if buy_result.is_a?(Hash) && buy_result[:success] == false
            # Return validation error
            buy_result
          elsif buy_result
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

          if sell_result.is_a?(Hash) && sell_result[:success] == false
            # Return validation error
            sell_result
          elsif sell_result
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

      # Place order with idempotency support - returns Dhan-compatible format
      def place_order!(symbol:, instrument_id:, side:, quantity:, price:, order_type: "MARKET", idempotency_key: nil, redis_store: nil)
        # Check for existing order if idempotency key is provided
        if idempotency_key && redis_store
          existing_order_id = redis_store.get_idempotency_key(idempotency_key)
          if existing_order_id
            @logger.info("[PAPER] Idempotency key found: #{idempotency_key} -> #{existing_order_id}, returning existing order")

            # Get the existing order from virtual data manager
            existing_order = @virtual_data_manager&.get_order_by_id(existing_order_id)
            if existing_order
              return create_dhan_compatible_response(
                order_id: existing_order_id,
                side: side,
                quantity: quantity,
                price: price,
                position: get_position_for_order(existing_order),
                idempotent: true,
                existing_order: get_order_object(existing_order)
              )
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

        # Convert to Dhan-compatible format
        if result[:success]
          create_dhan_compatible_response(
            order_id: result[:order_id],
            side: side,
            quantity: quantity,
            price: price,
            position: result[:position]
          )
        else
          create_dhan_error_response(result[:error])
        end
      end

      private


      # Create validation error object
      def create_validation_error(error_code, message)
        {
          success: false,
          error: error_code,
          error_message: message,
          order_id: nil,
          order: nil,
          position: nil
        }
      end

      # Create Dhan-compatible order response
      def create_dhan_compatible_response(order_id:, side:, quantity:, price:, position: nil, idempotent: false, existing_order: nil)
        {
          order_id: order_id,
          order_status: "FILLED",
          average_traded_price: price.to_f,
          filled_qty: quantity.to_i,
          remaining_quantity: 0,
          transaction_type: side.upcase,
          exchange_segment: "NSE_FO", # Default to options segment
          product_type: "MARGIN",
          order_type: "MARKET",
          validity: "DAY",
          security_id: position&.dig(:security_id) || "UNKNOWN",
          symbol: position&.dig(:symbol) || "UNKNOWN",
          buy_avg: position&.dig(:buy_avg)&.to_f || 0.0,
          buy_qty: position&.dig(:buy_qty)&.to_i || 0,
          sell_avg: position&.dig(:sell_avg)&.to_f || 0.0,
          sell_qty: position&.dig(:sell_qty)&.to_i || 0,
          net_qty: position&.dig(:net_qty)&.to_i || quantity.to_i,
          realized_profit: position&.dig(:realized_pnl)&.to_f || 0.0,
          unrealized_profit: position&.dig(:unrealized_pnl)&.to_f || 0.0,
          multiplier: position&.dig(:multiplier)&.to_i || 1,
          lot_size: position&.dig(:lot_size)&.to_i || 75,
          option_type: position&.dig(:option_type) || nil,
          strike_price: position&.dig(:strike_price)&.to_f || nil,
          expiry_date: position&.dig(:expiry_date) || nil,
          underlying_symbol: position&.dig(:underlying_symbol) || nil,
          timestamp: Time.now.iso8601,
          idempotent: idempotent ? true : nil,
          # Backward compatibility fields
          success: true,
          order: existing_order || {
            id: order_id,
            security_id: position&.dig(:security_id) || "UNKNOWN",
            side: side.upcase,
            quantity: quantity.to_i,
            price: price.to_f,
            timestamp: Time.now
          }
        }
      end

      # Create Dhan-compatible error response
      def create_dhan_error_response(error_message)
        {
          order_id: nil,
          order_status: "REJECTED",
          average_traded_price: 0.0,
          filled_qty: 0,
          remaining_quantity: 0,
          transaction_type: nil,
          exchange_segment: "NSE_FO",
          product_type: "MARGIN",
          order_type: "MARKET",
          validity: "DAY",
          security_id: nil,
          symbol: nil,
          buy_avg: 0.0,
          buy_qty: 0,
          sell_avg: 0.0,
          sell_qty: 0,
          net_qty: 0,
          realized_profit: 0.0,
          unrealized_profit: 0.0,
          multiplier: 1,
          lot_size: 75,
          option_type: nil,
          strike_price: nil,
          expiry_date: nil,
          underlying_symbol: nil,
          timestamp: Time.now.iso8601,
          error: error_message,
          rejection_reason: error_message,
          # Backward compatibility fields
          success: false,
          order: nil
        }
      end

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

      # Get order object for an existing order
      def get_order_object(order)
        return nil unless order

        # Return the order object as-is if it's already in the expected format
        if order.is_a?(Hash) && order[:id]
          order
        else
          # Convert to expected format if needed
          {
            id: order[:id] || order["id"],
            security_id: order[:security_id] || order["security_id"],
            side: order[:side] || order["side"],
            quantity: order[:quantity] || order["quantity"],
            price: order[:avg_price] || order[:price] || order["avg_price"] || order["price"],
            timestamp: order[:timestamp] || order["timestamp"]
          }
        end
      end
    end
  end
end
