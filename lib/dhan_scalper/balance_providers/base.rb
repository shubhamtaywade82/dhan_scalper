# frozen_string_literal: true

module DhanScalper
  module BalanceProviders
    class Base
      def available_balance
        raise NotImplementedError, "#{self.class} must implement #available_balance"
      end

      def total_balance
        raise NotImplementedError, "#{self.class} must implement #total_balance"
      end

      def used_balance
        raise NotImplementedError, "#{self.class} must implement #used_balance"
      end

      def update_balance(amount, type: :debit)
        raise NotImplementedError, "#{self.class} must implement #update_balance"
      end
    end
  end
end
