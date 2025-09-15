# frozen_string_literal: true

require_relative '../support/money'

module DhanScalper
  module Services
    # Equity calculator that combines balance and unrealized PnL
    class EquityCalculator
      def initialize(balance_provider:, position_tracker:, logger: Logger.new($stdout))
        @balance_provider = balance_provider
        @position_tracker = position_tracker
        @logger = logger
      end

      # Calculate total equity: balance + unrealized PnL
      def calculate_equity
        balance = @balance_provider.total_balance
        unrealized_pnl = calculate_total_unrealized_pnl

        total_equity = DhanScalper::Support::Money.add(balance, unrealized_pnl)

        @logger.debug("[EQUITY] Balance: ₹#{DhanScalper::Support::Money.dec(balance)}, Unrealized: ₹#{DhanScalper::Support::Money.dec(unrealized_pnl)}, Total: ₹#{DhanScalper::Support::Money.dec(total_equity)}")

        {
          balance: balance,
          unrealized_pnl: unrealized_pnl,
          total_equity: total_equity
        }
      end

      # Refresh unrealized PnL for a specific position
      def refresh_unrealized!(exchange_segment:, security_id:, current_ltp:)
        position = @position_tracker.get_position(
          exchange_segment: exchange_segment,
          security_id: security_id,
          side: 'LONG'
        )

        return { success: false, error: 'Position not found' } unless position

        # Calculate unrealized PnL based on option type
        current_ltp_bd = DhanScalper::Support::Money.bd(current_ltp)
        buy_avg_bd = position[:buy_avg]
        net_qty_bd = position[:net_qty]
        option_type = position[:option_type]

        # Use correct formula based on option type
        price_diff = if %w[PE PUT].include?(option_type)
                       # Put options: PnL = (Entry - Current) * Quantity
                       DhanScalper::Support::Money.subtract(buy_avg_bd, current_ltp_bd)
                     else
                       # Call options (CE/CALL) or default: PnL = (Current - Entry) * Quantity
                       DhanScalper::Support::Money.subtract(current_ltp_bd, buy_avg_bd)
                     end

        unrealized_pnl = DhanScalper::Support::Money.multiply(price_diff, net_qty_bd)

        # Update position with new unrealized PnL
        @position_tracker.update_position_unrealized_pnl(
          exchange_segment: exchange_segment,
          security_id: security_id,
          side: 'LONG',
          unrealized_pnl: unrealized_pnl
        )

        @logger.info("[MTM] #{security_id} | LTP: ₹#{DhanScalper::Support::Money.dec(current_ltp_bd)} | Unrealized: ₹#{DhanScalper::Support::Money.dec(unrealized_pnl)}")

        {
          success: true,
          unrealized_pnl: unrealized_pnl,
          current_ltp: current_ltp_bd,
          net_qty: net_qty_bd,
          buy_avg: buy_avg_bd
        }
      end

      # Refresh unrealized PnL for all positions
      def refresh_all_unrealized!(ltp_provider: nil)
        total_unrealized = DhanScalper::Support::Money.bd(0)
        updated_positions = []

        @position_tracker.get_positions.each do |position|
          next unless DhanScalper::Support::Money.positive?(position[:net_qty])

          # Get current LTP
          current_ltp = if ltp_provider
                          ltp_provider.call(position[:exchange_segment], position[:security_id])
                        else
                          # Fallback to position's current price
                          position[:current_price] || position[:buy_avg]
                        end

          next unless current_ltp

          result = refresh_unrealized!(
            exchange_segment: position[:exchange_segment],
            security_id: position[:security_id],
            current_ltp: current_ltp
          )

          next unless result[:success]

          total_unrealized = DhanScalper::Support::Money.add(total_unrealized, result[:unrealized_pnl])
          updated_positions << {
            security_id: position[:security_id],
            unrealized_pnl: result[:unrealized_pnl]
          }
        end

        @logger.info("[MTM] Refreshed #{updated_positions.length} positions | Total unrealized: ₹#{DhanScalper::Support::Money.dec(total_unrealized)}")

        {
          success: true,
          total_unrealized: total_unrealized,
          updated_positions: updated_positions
        }
      end

      # Get detailed equity breakdown
      def get_equity_breakdown
        balance = @balance_provider.total_balance
        realized_pnl = @balance_provider.realized_pnl
        unrealized_pnl = calculate_total_unrealized_pnl
        total_equity = DhanScalper::Support::Money.add(balance, unrealized_pnl)

        {
          starting_balance: @balance_provider.instance_variable_get(:@starting_balance),
          available_balance: @balance_provider.available_balance,
          used_balance: @balance_provider.used_balance,
          total_balance: balance,
          realized_pnl: realized_pnl,
          unrealized_pnl: unrealized_pnl,
          total_equity: total_equity,
          positions: get_position_breakdown
        }
      end

      private

      # Calculate total unrealized PnL across all positions
      def calculate_total_unrealized_pnl
        total_unrealized = DhanScalper::Support::Money.bd(0)

        @position_tracker.get_positions.each do |position|
          next unless DhanScalper::Support::Money.positive?(position[:net_qty])

          # Use current price if available, otherwise use buy average
          current_price = position[:current_price] || position[:buy_avg]
          buy_avg = position[:buy_avg]
          net_qty = position[:net_qty]
          option_type = position[:option_type]

          # Use correct formula based on option type
          price_diff = if %w[PE PUT].include?(option_type)
                         # Put options: PnL = (Entry - Current) * Quantity
                         DhanScalper::Support::Money.subtract(buy_avg, current_price)
                       else
                         # Call options (CE/CALL) or default: PnL = (Current - Entry) * Quantity
                         DhanScalper::Support::Money.subtract(current_price, buy_avg)
                       end

          unrealized = DhanScalper::Support::Money.multiply(price_diff, net_qty)

          total_unrealized = DhanScalper::Support::Money.add(total_unrealized, unrealized)
        end

        total_unrealized
      end

      # Get detailed breakdown of all positions
      def get_position_breakdown
        @position_tracker.get_positions.filter_map do |position|
          next unless DhanScalper::Support::Money.positive?(position[:net_qty])

          current_price = position[:current_price] || position[:buy_avg]
          unrealized = DhanScalper::Support::Money.multiply(
            DhanScalper::Support::Money.subtract(current_price, position[:buy_avg]),
            position[:net_qty]
          )

          {
            security_id: position[:security_id],
            exchange_segment: position[:exchange_segment],
            side: position[:side],
            net_qty: position[:net_qty],
            buy_avg: position[:buy_avg],
            current_price: current_price,
            unrealized_pnl: unrealized,
            market_value: DhanScalper::Support::Money.multiply(current_price, position[:net_qty])
          }
        end
      end
    end
  end
end
