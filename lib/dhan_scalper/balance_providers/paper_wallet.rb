# frozen_string_literal: true

require_relative "base"
require_relative "../support/money"

module DhanScalper
  module BalanceProviders
    class PaperWallet < Base
      def initialize(starting_balance: 200_000.0)
        super()
        @starting_balance = DhanScalper::Support::Money.bd(starting_balance)
        @available = @starting_balance
        @used = DhanScalper::Support::Money.bd(0)
        @total = @starting_balance
        @realized_pnl = DhanScalper::Support::Money.bd(0)
      end

      def available_balance
        @available
      end

      def total_balance
        @total
      end

      def used_balance
        @used
      end

      def update_balance(amount, type: :debit)
        amount_bd = DhanScalper::Support::Money.bd(amount)

        case type
        when :debit
          @available = DhanScalper::Support::Money.subtract(@available, amount_bd)
          @used = DhanScalper::Support::Money.add(@used, amount_bd)
        when :credit
          @available = DhanScalper::Support::Money.add(@available, amount_bd)
          @used = DhanScalper::Support::Money.subtract(@used, amount_bd)
        end

        # Ensure used balance doesn't go negative
        @used = DhanScalper::Support::Money.max(@used, DhanScalper::Support::Money.bd(0))
        @total = DhanScalper::Support::Money.add(@available, @used)
        @total
      end

      def reset_balance(amount)
        @starting_balance = DhanScalper::Support::Money.bd(amount)
        @available = @starting_balance
        @used = DhanScalper::Support::Money.bd(0)
        @total = @starting_balance
        @realized_pnl = DhanScalper::Support::Money.bd(0)
        @total
      end

      # Update total balance to reflect current market value
      def update_total_with_pnl(unrealized_pnl)
        unrealized_pnl_bd = DhanScalper::Support::Money.bd(unrealized_pnl)
        @total = DhanScalper::Support::Money.add(
          DhanScalper::Support::Money.add(@starting_balance, @realized_pnl),
          unrealized_pnl_bd
        )
        @total
      end

      def add_realized_pnl(pnl)
        pnl_bd = DhanScalper::Support::Money.bd(pnl)
        @realized_pnl = DhanScalper::Support::Money.add(@realized_pnl, pnl_bd)
        # Note: Realized PnL is tracked separately for reporting only
        # Cash flow is handled separately in update_balance
        @total
      end

      # Get realized PnL for reporting
      def realized_pnl
        @realized_pnl
      end
    end
  end
end
