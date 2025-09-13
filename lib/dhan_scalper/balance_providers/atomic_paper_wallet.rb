# frozen_string_literal: true

require_relative "base"
require_relative "../support/money"
require_relative "../support/logger"
require_relative "../support/validations"
require_relative "../support/atomic_state_manager"

module DhanScalper
  module BalanceProviders
    class AtomicPaperWallet < Base
      def initialize(starting_balance: 200_000.0, redis_url: nil)
        super()
        @state_manager = DhanScalper::Support::AtomicStateManager.new(redis_url: redis_url)
        @starting_balance = DhanScalper::Support::Money.bd(starting_balance)

        # Initialize state if not exists
        initialize_state
      end

      def available_balance
        snapshot = @state_manager.balance_snapshot
        snapshot[:available]
      end

      def used_balance
        snapshot = @state_manager.balance_snapshot
        snapshot[:used]
      end

      def total_balance
        snapshot = @state_manager.balance_snapshot
        # Total balance should be available + used + realized PnL
        result = DhanScalper::Support::Money.add(snapshot[:available], snapshot[:used])
        result = DhanScalper::Support::Money.add(result, snapshot[:realized_pnl])

        DhanScalper::Support::Logger.debug(
          "Total balance calculated - available: #{DhanScalper::Support::Money.dec(snapshot[:available])}, " \
          "used: #{DhanScalper::Support::Money.dec(snapshot[:used])}, " \
          "realized_pnl: #{DhanScalper::Support::Money.dec(snapshot[:realized_pnl])}, " \
          "result: #{DhanScalper::Support::Money.dec(result)}",
          component: "AtomicPaperWallet"
        )
        result
      end

      def realized_pnl
        snapshot = @state_manager.balance_snapshot
        snapshot[:realized_pnl]
      end

      def update_balance(amount, type: :debit)
        DhanScalper::Support::Validations.validate_price_positive(amount)

        @state_manager.atomic_balance_update("update_balance") do |state|
          amount_bd = DhanScalper::Support::Money.bd(amount)

          DhanScalper::Support::Logger.debug(
            "Updating balance - amount: #{DhanScalper::Support::Money.dec(amount_bd)}, " \
            "type: #{type}, available before: #{DhanScalper::Support::Money.dec(state[:available])}, " \
            "used before: #{DhanScalper::Support::Money.dec(state[:used])}",
            component: "AtomicPaperWallet"
          )

          case type
          when :debit
            DhanScalper::Support::Validations.validate_balance_sufficient(state[:available], amount)
            state[:available] = DhanScalper::Support::Money.subtract(state[:available], amount_bd)
            state[:used] = DhanScalper::Support::Money.add(state[:used], amount_bd)
          when :credit
            state[:available] = DhanScalper::Support::Money.add(state[:available], amount_bd)
          when :release_principal
            # Release principal from used balance and add it back to available balance
            state[:used] = DhanScalper::Support::Money.subtract(state[:used], amount_bd)
            state[:available] = DhanScalper::Support::Money.add(state[:available], amount_bd)
          end

          # Ensure used balance doesn't go negative
          state[:used] = DhanScalper::Support::Money.max(state[:used], DhanScalper::Support::Money.bd(0))
          state[:total] = DhanScalper::Support::Money.add(state[:available], state[:used])

          DhanScalper::Support::Logger.debug(
            "Balance updated - available after: #{DhanScalper::Support::Money.dec(state[:available])}, " \
            "used after: #{DhanScalper::Support::Money.dec(state[:used])}, " \
            "total: #{DhanScalper::Support::Money.dec(state[:total])}",
            component: "AtomicPaperWallet"
          )

          state
        end
      end

      def debit_for_buy(principal_cost:, fee: 0)
        DhanScalper::Support::Validations.validate_price_positive(principal_cost)
        DhanScalper::Support::Validations.validate_price_positive(fee)

        @state_manager.atomic_balance_update("debit_for_buy") do |state|
          principal_bd = DhanScalper::Support::Money.bd(principal_cost)
          fee_bd = DhanScalper::Support::Money.bd(fee)

          DhanScalper::Support::Logger.debug(
            "Debiting for buy - principal: #{DhanScalper::Support::Money.dec(principal_bd)}, " \
            "fee: #{DhanScalper::Support::Money.dec(fee_bd)}",
            component: "AtomicPaperWallet"
          )

          total_cost = DhanScalper::Support::Money.add(principal_bd, fee_bd)
          DhanScalper::Support::Validations.validate_balance_sufficient(state[:available], total_cost)

          state[:available] = DhanScalper::Support::Money.subtract(state[:available], total_cost)
          state[:used] = DhanScalper::Support::Money.add(state[:used], total_cost)
          state[:total] = DhanScalper::Support::Money.add(state[:available], state[:used])

          DhanScalper::Support::Logger.debug(
            "Buy debit completed - available: #{DhanScalper::Support::Money.dec(state[:available])}, " \
            "used: #{DhanScalper::Support::Money.dec(state[:used])}, " \
            "total: #{DhanScalper::Support::Money.dec(state[:total])}",
            component: "AtomicPaperWallet"
          )

          state
        end
      end

      def credit_for_sell(net_proceeds:, released_principal:)
        @state_manager.atomic_balance_update("credit_for_sell") do |state|
          net_bd = DhanScalper::Support::Money.bd(net_proceeds)
          released_bd = DhanScalper::Support::Money.bd(released_principal)

          DhanScalper::Support::Logger.debug(
            "Crediting for sell - net_proceeds: #{DhanScalper::Support::Money.dec(net_bd)}, " \
            "released_principal: #{DhanScalper::Support::Money.dec(released_bd)}",
            component: "AtomicPaperWallet"
          )

          # Credit the actual cash received from the sale
          state[:available] = DhanScalper::Support::Money.add(state[:available], net_bd)

          # Release the principal that was tied up in the position
          state[:used] = DhanScalper::Support::Money.subtract(state[:used], released_bd)
          state[:used] = DhanScalper::Support::Money.max(state[:used], DhanScalper::Support::Money.bd(0))

          # Total balance is available + used (no double counting)
          state[:total] = DhanScalper::Support::Money.add(state[:available], state[:used])

          DhanScalper::Support::Logger.debug(
            "Sell credit completed - available: #{DhanScalper::Support::Money.dec(state[:available])}, " \
            "used: #{DhanScalper::Support::Money.dec(state[:used])}, " \
            "total: #{DhanScalper::Support::Money.dec(state[:total])}",
            component: "AtomicPaperWallet"
          )

          state
        end
      end

      def reset_balance(amount)
        @state_manager.atomic_balance_update("reset_balance") do |state|
          new_balance = DhanScalper::Support::Money.bd(amount)
          state[:starting_balance] = new_balance
          state[:available] = new_balance
          state[:used] = DhanScalper::Support::Money.bd(0)
          state[:total] = new_balance
          state[:realized_pnl] = DhanScalper::Support::Money.bd(0)
          state
        end
      end

      def add_realized_pnl(pnl)
        @state_manager.atomic_balance_update("add_realized_pnl") do |state|
          pnl_bd = DhanScalper::Support::Money.bd(pnl)
          state[:realized_pnl] = DhanScalper::Support::Money.add(state[:realized_pnl], pnl_bd)

          DhanScalper::Support::Logger.debug(
            "Added realized PnL: #{DhanScalper::Support::Money.dec(pnl)}, " \
            "realized_pnl now: #{DhanScalper::Support::Money.dec(state[:realized_pnl])}",
            component: "AtomicPaperWallet"
          )

          state
        end
      end

      def add_to_used_balance(amount)
        DhanScalper::Support::Validations.validate_price_positive(amount)

        @state_manager.atomic_balance_update("add_to_used_balance") do |state|
          amount_bd = DhanScalper::Support::Money.bd(amount)

          state[:used] = DhanScalper::Support::Money.add(state[:used], amount_bd)
          state[:total] = DhanScalper::Support::Money.add(state[:available], state[:used])

          DhanScalper::Support::Logger.debug(
            "Added to used balance - amount: #{DhanScalper::Support::Money.dec(amount_bd)}, " \
            "used after: #{DhanScalper::Support::Money.dec(state[:used])}",
            component: "AtomicPaperWallet"
          )

          state
        end
      end

      def clear_used_balance
        @state_manager.atomic_balance_update("clear_used_balance") do |state|
          state[:used] = DhanScalper::Support::Money.bd(0)
          state[:total] = DhanScalper::Support::Money.add(state[:available], state[:used])
          state
        end
      end

      def update_total_with_pnl(unrealized_pnl)
        @state_manager.atomic_balance_update("update_total_with_pnl") do |state|
          unrealized_pnl_bd = DhanScalper::Support::Money.bd(unrealized_pnl)
          state[:total] = DhanScalper::Support::Money.add(
            DhanScalper::Support::Money.add(state[:starting_balance], state[:realized_pnl]),
            unrealized_pnl_bd,
          )
          state
        end
      end

      # Get a consistent snapshot of the current state
      def state_snapshot
        @state_manager.balance_snapshot
      end

      # Reset all state (useful for testing)
      def reset_state
        @state_manager.reset_state
      end

      private

      def initialize_state
        current_state = @state_manager.balance_snapshot

        # Always initialize with the specified starting balance
        # This ensures the wallet starts with the correct amount
        reset_balance(@starting_balance)
      end
    end
  end
end
