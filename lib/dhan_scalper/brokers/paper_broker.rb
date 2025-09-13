# frozen_string_literal: true

require_relative "../support/money"
require_relative "../support/logger"
require_relative "../support/validations"
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
        DhanScalper::Support::Logger.info(
          "Buying market: #{segment}, #{security_id}, #{quantity}, #{charge_per_order}",
          component: "PaperBroker",
        )

        # Validate inputs
        DhanScalper::Support::Validations.validate_instrument_id(security_id)
        DhanScalper::Support::Validations.validate_segment(segment)
        DhanScalper::Support::Validations.validate_quantity(quantity, 1) # Basic quantity validation

        price = DhanScalper::TickCache.ltp(segment, security_id)
        unless price&.positive?
          error_msg = "No valid price available for #{security_id}"
          DhanScalper::Support::Logger.error(error_msg, component: "PaperBroker")
          return create_validation_error("INVALID_PRICE", error_msg)
        end

        # Convert to BigDecimal for safe money calculations
        price_bd = DhanScalper::Support::Money.bd(price)
        quantity_bd = DhanScalper::Support::Money.bd(quantity)
        # Default fee to configured value if not provided
        fee_value = charge_per_order.nil? ? DhanScalper::Config.fee : charge_per_order
        charge_bd = DhanScalper::Support::Money.bd(fee_value)

        # Calculate principal cost and total cost: principal = price * quantity; total = principal + fee
        principal_cost = DhanScalper::Support::Money.multiply(price_bd, quantity_bd)
        total_cost = DhanScalper::Support::Money.add(principal_cost, charge_bd)

        # Check if we can afford this position
        if @balance_provider && @balance_provider.available_balance < total_cost
          error_msg = "Insufficient balance. Need ₹#{DhanScalper::Support::Money.dec(total_cost)}, have ₹#{DhanScalper::Support::Money.dec(@balance_provider.available_balance)}"
          @logger.warn("[PAPER] #{error_msg}")
          return create_validation_error("INSUFFICIENT_BALANCE", error_msg)
        end

        # Debit the balance using principal vs fee split
        @balance_provider&.debit_for_buy(principal_cost: principal_cost, fee: charge_bd)

        # Add position to enhanced tracker
        position = @position_tracker.add_position(
          exchange_segment: segment,
          security_id: security_id,
          side: "LONG",
          quantity: quantity,
          price: price,
          fee: charge_per_order,
        )

        order = Order.new("P-#{Time.now.to_f}", security_id, "BUY", quantity, price)

        # Log the order
        log_order(order)

        @logger.info("[PAPER] Position added: #{security_id} | Qty: #{DhanScalper::Support::Money.dec(quantity_bd)} @ ₹#{DhanScalper::Support::Money.dec(price_bd)} | Avg: ₹#{DhanScalper::Support::Money.dec(position[:buy_avg])} | Net Qty: #{DhanScalper::Support::Money.dec(position[:net_qty])}")

        order
      end

      def sell_market(segment:, security_id:, quantity:, charge_per_order: 20)
        DhanScalper::Support::Logger.info(
          "Selling market: #{segment}, #{security_id}, #{quantity}, #{charge_per_order}",
          component: "PaperBroker",
        )

        # Validate inputs
        DhanScalper::Support::Validations.validate_instrument_id(security_id)
        DhanScalper::Support::Validations.validate_segment(segment)
        DhanScalper::Support::Validations.validate_quantity(quantity, 1) # Basic quantity validation

        price = DhanScalper::TickCache.ltp(segment, security_id)
        unless price&.positive?
          error_msg = "No valid price available for #{security_id}"
          DhanScalper::Support::Logger.error(error_msg, component: "PaperBroker")
          return create_validation_error("INVALID_PRICE", error_msg)
        end

        # Convert to BigDecimal for safe money calculations
        price_bd = DhanScalper::Support::Money.bd(price)
        quantity_bd = DhanScalper::Support::Money.bd(quantity)
        fee_value = charge_per_order.nil? ? DhanScalper::Config.fee : charge_per_order

        # Check if we have sufficient position to sell
        position = @position_tracker.get_position(
          exchange_segment: segment,
          security_id: security_id,
          side: "LONG",
        )

        unless position && position[:net_qty] && DhanScalper::Support::Money.greater_than_or_equal?(position[:net_qty],
                                                                                                    quantity_bd)
          available_qty = position&.dig(:net_qty) || 0
          error_msg = "Insufficient position. Trying to sell #{DhanScalper::Support::Money.dec(quantity_bd)}, have #{DhanScalper::Support::Money.dec(available_qty)}"
          DhanScalper::Support::Logger.warn("[PAPER] #{error_msg}", component: "PaperBroker")
          return create_validation_error("INSUFFICIENT_POSITION", error_msg)
        end

        # Additional oversell protection using validation module
        begin
          DhanScalper::Support::Validations.validate_position_sufficient(
            DhanScalper::Support::Money.dec(position[:net_qty]),
            DhanScalper::Support::Money.dec(quantity_bd),
          )
        rescue DhanScalper::OversellError => e
          DhanScalper::Support::Logger.error(e.message, component: "PaperBroker")
          return create_validation_error("OVERSELL", e.message)
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
          fee: charge_per_order,
        )

        if result
          # Calculate the weighted average cost of the sold quantity
          sold_quantity = result[:sold_quantity]
          weighted_avg_cost_per_unit = position[:buy_avg]
          weighted_avg_cost = DhanScalper::Support::Money.multiply(weighted_avg_cost_per_unit, sold_quantity)

          # Calculate the proportion of entry fee for this partial exit
          total_position_qty = position[:buy_qty]
          entry_fee_proportion = DhanScalper::Support::Money.divide(sold_quantity, total_position_qty)
          DhanScalper::Support::Money.multiply(
            position[:entry_fee] || DhanScalper::Support::Money.bd(0), entry_fee_proportion
          )

          # Credit the net proceeds (price × quantity - exit fee)
          @balance_provider&.update_balance(result[:net_proceeds], type: :credit)

          # Add exit fee to used balance without deducting from available
          @balance_provider&.add_to_used_balance(fee_value)

          # Release only the principal (premium) from used balance, keep entry fee in used balance
          @balance_provider&.update_balance(weighted_avg_cost, type: :release_principal)

          # Update realized PnL in balance provider (for reporting only)
          @balance_provider&.add_realized_pnl(result[:realized_pnl])

          @logger.info("[PAPER] Partial exit: #{security_id} | Sold: #{DhanScalper::Support::Money.dec(result[:sold_quantity])} @ ₹#{DhanScalper::Support::Money.dec(price_bd)} | Realized PnL: ₹#{DhanScalper::Support::Money.dec(result[:realized_pnl])} | Net Proceeds: ₹#{DhanScalper::Support::Money.dec(result[:net_proceeds])} | Released: ₹#{DhanScalper::Support::Money.dec(weighted_avg_cost)} | Remaining: #{DhanScalper::Support::Money.dec(result[:position]&.dig(:net_qty) || 0)}")
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

        # Determine the correct segment based on the instrument
        segment = determine_segment(symbol, instrument_id)

        case side.upcase
        when "BUY"
          # Use buy_market method for consistency
          buy_result = buy_market(segment: segment, security_id: instrument_id, quantity: quantity,
                                  charge_per_order: 20)

          if buy_result.is_a?(Hash) && buy_result[:success] == false
            # Return validation error
            buy_result
          elsif buy_result
            position = @position_tracker.get_position(exchange_segment: segment, security_id: instrument_id,
                                                      side: "LONG")
            {
              success: true,
              order_id: order_id,
              order: order,
              position: position,
            }
          else
            {
              success: false,
              error: "Failed to execute buy order",
            }
          end

        when "SELL"
          # Use sell_market method for consistency
          sell_result = sell_market(segment: segment, security_id: instrument_id, quantity: quantity,
                                    charge_per_order: 20)

          if sell_result.is_a?(Hash) && sell_result[:success] == false
            # Return validation error
            sell_result
          elsif sell_result
            position = @position_tracker.get_position(exchange_segment: segment, security_id: instrument_id,
                                                      side: "LONG")
            {
              success: true,
              order_id: order_id,
              order: order,
              position: position,
            }
          else
            {
              success: false,
              error: "Failed to execute sell order",
            }
          end

        else
          {
            success: false,
            error: "Invalid side: #{side}. Use 'BUY' or 'SELL'",
          }
        end
      end

      # Get position tracker for external access
      attr_reader :position_tracker

      # Get balance provider for external access
      attr_reader :balance_provider

      # Place order with idempotency support - returns Dhan-compatible format
      def place_order!(symbol:, instrument_id:, side:, quantity:, price:, order_type: "MARKET", idempotency_key: nil,
                       redis_store: nil)
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
                existing_order: get_order_object(existing_order),
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
          order_type: order_type,
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
            position: result[:position],
          )
        else
          create_dhan_error_response(result[:error])
        end
      end

      private

      # Determine the correct segment based on symbol and security_id
      def determine_segment(symbol, security_id)
        return "NSE_FNO" unless symbol && security_id

        # Use CsvMaster to determine the correct segment
        begin
          csv_master = DhanScalper::CsvMaster.new
          segment = csv_master.get_exchange_segment(security_id)
          return segment if segment
        rescue StandardError => e
          @logger.warn("[PAPER] Failed to determine segment for #{symbol}:#{security_id}: #{e.message}")
        end

        # Fallback logic based on symbol
        case symbol.to_s.upcase
        when /SENSEX/
          "BSE_FNO"
        when /NIFTY|BANKNIFTY/
          "NSE_FNO"
        else
          "NSE_EQ" # Default to NSE_EQ when unknown
        end
      end

      # Create validation error object
      def create_validation_error(error_code, message)
        {
          success: false,
          error: error_code,
          error_message: message,
          order_id: nil,
          order: nil,
          position: nil,
        }
      end

      # Create Dhan-compatible order response
      def create_dhan_compatible_response(order_id:, side:, quantity:, price:, position: nil, idempotent: false,
                                          existing_order: nil)
        {
          order_id: order_id,
          order_status: "FILLED",
          average_traded_price: price.to_f,
          filled_qty: quantity.to_i,
          remaining_quantity: 0,
          transaction_type: side.upcase,
          exchange_segment: position&.dig(:exchange_segment) || "NSE_FNO", # Use position segment or default to NSE_FNO
          product_type: "MARGIN",
          order_type: "MARKET",
          validity: "DAY",
          security_id: position&.dig(:security_id) || "UNKNOWN",
          symbol: position&.dig(:symbol) || "UNKNOWN",
          buy_avg: position&.dig(:buy_avg).to_f,
          buy_qty: position&.dig(:buy_qty).to_i,
          sell_avg: position&.dig(:sell_avg).to_f,
          sell_qty: position&.dig(:sell_qty).to_i,
          net_qty: position&.dig(:net_qty)&.to_i || quantity.to_i,
          realized_profit: position&.dig(:realized_pnl).to_f,
          unrealized_profit: position&.dig(:unrealized_pnl).to_f,
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
            timestamp: Time.now,
          },
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
          exchange_segment: "NSE_FNO", # Default to NSE_FNO for derivatives
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
          order: nil,
        }
      end

      # Get position for an existing order
      def get_position_for_order(order)
        return nil unless order

        # Determine the correct segment for the order
        security_id = order[:security_id] || order["security_id"]
        symbol = order[:symbol] || order["symbol"]
        segment = determine_segment(symbol, security_id)

        # Try to get position from enhanced tracker
        @position_tracker.get_position(
          exchange_segment: segment,
          security_id: security_id,
          side: "LONG",
        )
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
            timestamp: order[:timestamp] || order["timestamp"],
          }
        end
      end
    end
  end
end
