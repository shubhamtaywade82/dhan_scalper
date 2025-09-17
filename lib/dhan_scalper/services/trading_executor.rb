# frozen_string_literal: true

module DhanScalper
  module Services
    # Handles trade execution logic for paper trading
    class TradingExecutor
      def initialize(broker:, position_tracker:, balance_provider:, session_manager:, logger:)
        @broker = broker
        @position_tracker = position_tracker
        @balance_provider = balance_provider
        @session_manager = session_manager
        @logger = logger
      end

      def execute_trade(symbol, symbol_config, direction, spot_price, pick)
        return false unless direction && direction != :none

        # Get option details
        ce_sid = pick[:ce_sid][spot_price]
        pe_sid = pick[:pe_sid][spot_price]

        return false unless ce_sid && pe_sid

        # Determine which option to trade based on direction
        option_sid = direction == :long ? ce_sid : pe_sid
        option_type = direction == :long ? 'CE' : 'PE'

        # Calculate position size
        option_price = get_option_price(option_sid, spot_price, direction)
        return false unless option_price&.positive?

        quantity = calculate_position_size(symbol, option_price, symbol_config)
        return false if quantity <= 0

        # Execute the trade
        execute_buy_order(symbol, option_sid, option_type, quantity, option_price, spot_price)
      end

      def calculate_used_balance_from_positions(positions)
        return 0.0 if positions.nil? || positions.empty?

        # Calculate position values
        position_values = positions.sum do |position|
          quantity = position[:quantity] || position['quantity'] || 0
          entry_price = position[:entry_price] || position['entry_price'] || 0
          quantity * entry_price
        end

        # Calculate total fees (₹20 per order)
        fee_per_order = 20.0 # Default fee
        total_fees = positions.length * fee_per_order

        total_used = position_values + total_fees

        @logger.debug(
          "Calculated used balance from positions - positions: #{position_values}, fees: #{total_fees}, total: #{total_used}",
          component: 'TradingExecutor'
        )

        total_used
      end

      private

      def get_option_price(option_sid, spot_price, direction)
        # Get current price from tick cache
        tick = DhanScalper::TickCache.get('NSE_FNO', option_sid)
        return tick[:ltp] if tick && tick[:ltp]&.positive?

        # Fallback to theoretical price calculation
        calculate_theoretical_price(spot_price, direction)
      end

      def calculate_theoretical_price(spot_price, direction)
        # Simple theoretical price calculation for paper trading
        # This is a placeholder - in real implementation, you'd use Black-Scholes or similar
        base_price = spot_price * 0.01 # 1% of spot price as base
        direction == :long ? base_price * 1.1 : base_price * 0.9
      end

      def calculate_position_size(_symbol, option_price, symbol_config)
        # Simple position sizing - allocate 30% of available balance
        available_balance = @balance_provider.available_balance
        allocation_pct = 0.30
        allocated_amount = available_balance * allocation_pct

        # Calculate quantity based on option price
        quantity = (allocated_amount / option_price).to_i

        # Apply lot size constraint
        lot_size = symbol_config['lot_size'] || 75
        quantity = (quantity / lot_size) * lot_size

        # Ensure minimum quantity
        [quantity, lot_size].max
      end

      def execute_buy_order(symbol, option_sid, option_type, quantity, option_price, spot_price)
        # Place buy order
        order_result = @broker.buy_market(
          segment: 'NSE_FNO',
          security_id: option_sid,
          quantity: quantity,
          charge_per_order: 20.0
        )

        if order_result[:success]
          # Track the trade
          @session_manager.add_trade({
                                       timestamp: Time.now.strftime('%H:%M:%S'),
                                       symbol: symbol,
                                       side: 'BUY',
                                       quantity: quantity,
                                       price: option_price,
                                       order_id: order_result[:order_id],
                                       option_type: option_type,
                                       strike: spot_price,
                                       spot_price: spot_price
                                     })

          @session_manager.increment_successful_trades

          # Add position to tracker
          @position_tracker.add_position(
            symbol: symbol,
            option_type: option_type,
            strike: spot_price,
            expiry: Date.today.strftime('%Y-%m-%d'),
            security_id: option_sid,
            quantity: quantity,
            entry_price: option_price
          )

          @logger.info "[TRADE] BUY #{quantity} #{symbol} #{option_type} @ ₹#{option_price}"
          true
        else
          @session_manager.add_trade({
                                       timestamp: Time.now.strftime('%H:%M:%S'),
                                       symbol: symbol,
                                       side: 'BUY',
                                       quantity: quantity,
                                       price: option_price,
                                       order_id: nil,
                                       error: order_result[:error],
                                       option_type: option_type,
                                       strike: spot_price,
                                       spot_price: spot_price
                                     })

          @session_manager.increment_failed_trades

          @logger.error "[TRADE] Failed to buy #{symbol} #{option_type}: #{order_result[:error]}"
          false
        end
      end
    end
  end
end
