# frozen_string_literal: true

require_relative "base"

module DhanScalper
  module BalanceProviders
    class PaperWallet < Base
      def initialize(starting_balance: 200_000.0)
        @available = starting_balance
        @used = 0.0
        @total = starting_balance
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
        @available = amount
        @used = 0.0
        @total = amount
        @total
      end
    end
  end
end
