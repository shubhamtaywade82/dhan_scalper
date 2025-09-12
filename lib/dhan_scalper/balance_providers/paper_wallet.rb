# frozen_string_literal: true

require_relative "base"
require_relative "../support/money"
require_relative "../support/logger"
require_relative "../support/validations"

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
        # Total balance should be available + used + realized PnL
        # Realized PnL represents the cumulative profit/loss from closed positions
        result = DhanScalper::Support::Money.add(@available, @used)
        result = DhanScalper::Support::Money.add(result, @realized_pnl)
        DhanScalper::Support::Logger.debug(
          "Total balance calculated - available: #{DhanScalper::Support::Money.dec(@available)}, " \
          "used: #{DhanScalper::Support::Money.dec(@used)}, " \
          "realized_pnl: #{DhanScalper::Support::Money.dec(@realized_pnl)}, " \
          "result: #{DhanScalper::Support::Money.dec(result)}",
          component: "PaperWallet"
        )
        result
      end

      def used_balance
        @used
      end

      def update_balance(amount, type: :debit)
        amount_bd = DhanScalper::Support::Money.bd(amount)
        DhanScalper::Support::Validations.validate_price_positive(amount)

        DhanScalper::Support::Logger.debug(
          "Updating balance - amount: #{DhanScalper::Support::Money.dec(amount_bd)}, " \
          "type: #{type}, available before: #{DhanScalper::Support::Money.dec(@available)}, " \
          "used before: #{DhanScalper::Support::Money.dec(@used)}",
          component: "PaperWallet"
        )

        case type
        when :debit
          DhanScalper::Support::Validations.validate_balance_sufficient(@available, amount)
          @available = DhanScalper::Support::Money.subtract(@available, amount_bd)
          @used = DhanScalper::Support::Money.add(@used, amount_bd)
        when :credit
          @available = DhanScalper::Support::Money.add(@available, amount_bd)
        when :release_principal
          # Release principal from used balance and add it back to available balance
          @used = DhanScalper::Support::Money.subtract(@used, amount_bd)
          @available = DhanScalper::Support::Money.add(@available, amount_bd)
        end

        # Ensure used balance doesn't go negative
        @used = DhanScalper::Support::Money.max(@used, DhanScalper::Support::Money.bd(0))
        @total = DhanScalper::Support::Money.add(@available, @used)

        DhanScalper::Support::Logger.debug(
          "Balance updated - available after: #{DhanScalper::Support::Money.dec(@available)}, " \
          "used after: #{DhanScalper::Support::Money.dec(@used)}, " \
          "total: #{DhanScalper::Support::Money.dec(@total)}",
          component: "PaperWallet"
        )
        @total
      end

      # Debit balance for a BUY: reduce available by (principal + fee), lock principal in used
      def debit_for_buy(principal_cost:, fee: 0)
        principal_bd = DhanScalper::Support::Money.bd(principal_cost)
        fee_bd = DhanScalper::Support::Money.bd(fee)

        DhanScalper::Support::Validations.validate_price_positive(principal_cost)
        DhanScalper::Support::Validations.validate_price_positive(fee)

        DhanScalper::Support::Logger.debug(
          "Debiting for buy - principal: #{DhanScalper::Support::Money.dec(principal_bd)}, " \
          "fee: #{DhanScalper::Support::Money.dec(fee_bd)}",
          component: "PaperWallet"
        )

        total_cost = DhanScalper::Support::Money.add(principal_bd, fee_bd)
        DhanScalper::Support::Validations.validate_balance_sufficient(@available, total_cost)

        @available = DhanScalper::Support::Money.subtract(@available, total_cost)
        @used = DhanScalper::Support::Money.add(@used, total_cost)
        @total = DhanScalper::Support::Money.add(@available, @used)

        DhanScalper::Support::Logger.debug(
          "Buy debit completed - available: #{DhanScalper::Support::Money.dec(@available)}, " \
          "used: #{DhanScalper::Support::Money.dec(@used)}, " \
          "total: #{DhanScalper::Support::Money.dec(@total)}",
          component: "PaperWallet"
        )
        @total
      end

      # Credit balance for a SELL: increase available by net proceeds, release principal from used
      def credit_for_sell(net_proceeds:, released_principal:)
        net_bd = DhanScalper::Support::Money.bd(net_proceeds)
        released_bd = DhanScalper::Support::Money.bd(released_principal)

        DhanScalper::Support::Logger.debug(
          "Crediting for sell - net_proceeds: #{DhanScalper::Support::Money.dec(net_bd)}, " \
          "released_principal: #{DhanScalper::Support::Money.dec(released_bd)}",
          component: "PaperWallet"
        )

        # Credit the actual cash received from the sale
        @available = DhanScalper::Support::Money.add(@available, net_bd)

        # Release the principal that was tied up in the position
        @used = DhanScalper::Support::Money.subtract(@used, released_bd)
        @used = DhanScalper::Support::Money.max(@used, DhanScalper::Support::Money.bd(0))

        # Total balance is available + used (no double counting)
        @total = DhanScalper::Support::Money.add(@available, @used)

        DhanScalper::Support::Logger.debug(
          "Sell credit completed - available: #{DhanScalper::Support::Money.dec(@available)}, " \
          "used: #{DhanScalper::Support::Money.dec(@used)}, " \
          "total: #{DhanScalper::Support::Money.dec(@total)}",
          component: "PaperWallet"
        )
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
          unrealized_pnl_bd,
        )
        @total
      end

      def add_realized_pnl(pnl)
        pnl_bd = DhanScalper::Support::Money.bd(pnl)
        @realized_pnl = DhanScalper::Support::Money.add(@realized_pnl, pnl_bd)
        # NOTE: Realized PnL is tracked separately for reporting only
        # Cash flow is already reflected in available/used balance
        DhanScalper::Support::Logger.debug(
          "Added realized PnL: #{DhanScalper::Support::Money.dec(pnl)}, " \
          "realized_pnl now: #{DhanScalper::Support::Money.dec(@realized_pnl)}",
          component: "PaperWallet"
        )
        @total
      end

      # Get realized PnL for reporting
      attr_reader :realized_pnl

      # Add amount to used balance without affecting available balance
      def add_to_used_balance(amount)
        amount_bd = DhanScalper::Support::Money.bd(amount)
        DhanScalper::Support::Validations.validate_price_positive(amount)

        @used = DhanScalper::Support::Money.add(@used, amount_bd)
        @total = DhanScalper::Support::Money.add(@available, @used)

        DhanScalper::Support::Logger.debug(
          "Added to used balance - amount: #{DhanScalper::Support::Money.dec(amount_bd)}, " \
          "used after: #{DhanScalper::Support::Money.dec(@used)}",
          component: "PaperWallet"
        )
        @total
      end

      # Clear used balance (for when positions are closed)
      def clear_used_balance
        @used = DhanScalper::Support::Money.bd(0)
        @total = DhanScalper::Support::Money.add(@available, @used)
      end
    end
  end
end
