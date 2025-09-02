# frozen_string_literal: true

require_relative "base"

module DhanScalper
  module BalanceProviders
    class PaperWallet < Base
      def initialize(starting_balance: 200_000.0)
        @starting_balance = starting_balance
        @available = starting_balance
        @used = 0.0
        @total = starting_balance
        @realized_pnl = 0.0
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
        case type
        when :debit
          @available -= amount
          @used += amount
        when :credit
          @available += amount
          @used -= amount
        end

        @total = @available + @used
        @total
      end

      def reset_balance(amount)
        @starting_balance = amount
        @available = amount
        @used = 0.0
        @total = amount
        @realized_pnl = 0.0
        @total
      end

      # Update total balance to reflect current market value
      def update_total_with_pnl(unrealized_pnl)
        @total = @starting_balance + @realized_pnl + unrealized_pnl
        @total
      end

      def add_realized_pnl(pnl)
        @realized_pnl += pnl
        @total = @starting_balance + @realized_pnl
        @total
      end
    end
  end
end
