# frozen_string_literal: true

require "csv"
require_relative "base"
require_relative "../support/money"
require_relative "../support/logger"
require_relative "../support/validations"
require_relative "../stores/redis_store"

module DhanScalper
  module BalanceProviders
    class PaperWallet < Base
      def initialize(starting_balance: 200_000.0, position_tracker: nil, session_id: nil, redis_store: nil)
        super()
        @starting_balance = DhanScalper::Support::Money.bd(starting_balance)
        @available = @starting_balance
        @used = DhanScalper::Support::Money.bd(0)
        @total = @starting_balance
        @realized_pnl = DhanScalper::Support::Money.bd(0)
        @position_tracker = position_tracker
        @session_id = session_id || generate_session_id
        @redis_store = redis_store || DhanScalper::Stores::RedisStore.new

        # Connect to Redis if not already connected
        @redis_store.connect unless @redis_store.redis

        # Load existing balance from Redis or initialize
        load_balance_from_redis
      end

      def available_balance
        # Calculate available balance as total - used
        total = total_balance
        used = used_balance
        available = total - used
        DhanScalper::Support::Logger.debug(
          "Calculated available balance - total: #{total}, used: #{used}, available: #{available}",
          component: "PaperWallet",
        )
        available
      end

      def total_balance
        # Total balance should remain constant (starting balance + realized PnL)
        # This represents the total capital available, not the current cash position
        result = DhanScalper::Support::Money.add(@starting_balance, @realized_pnl)
        DhanScalper::Support::Logger.debug(
          "Total balance calculated - starting: #{DhanScalper::Support::Money.dec(@starting_balance)}, " \
          "realized_pnl: #{DhanScalper::Support::Money.dec(@realized_pnl)}, " \
          "result: #{DhanScalper::Support::Money.dec(result)}",
          component: "PaperWallet",
        )
        DhanScalper::Support::Money.dec(result).to_f
      end

      def used_balance
        # Use internal state if it has been updated (non-zero used balance)
        # Otherwise fall back to session report calculation (for CLI commands with no activity)
        if @used > 0
          # Internal state has been updated, use it
          DhanScalper::Support::Money.dec(@used).to_f
        else
          # No internal activity, calculate from session report
          calculate_used_balance_from_positions
        end
      end

      def update_balance(amount, type: :debit)
        amount_bd = DhanScalper::Support::Money.bd(amount)

        # Skip validation for zero or negative amounts in edge cases
        unless amount == 0 || amount < 0
          DhanScalper::Support::Validations.validate_price_positive(amount)
        end

        DhanScalper::Support::Logger.debug(
          "Updating balance - amount: #{DhanScalper::Support::Money.dec(amount_bd)}, " \
          "type: #{type}, available before: #{DhanScalper::Support::Money.dec(@available)}, " \
          "used before: #{DhanScalper::Support::Money.dec(@used)}",
          component: "PaperWallet",
        )

        case type
        when :debit
          # For debit, validate sufficient balance but allow going to zero
          if amount > 0
            # Check if we have sufficient balance, if not, use all available
            if DhanScalper::Support::Money.less_than?(@available, amount_bd)
              # Not enough balance, use all available
              @used = DhanScalper::Support::Money.add(@used, @available)
              @available = DhanScalper::Support::Money.bd(0)
            else
              # Sufficient balance, proceed normally
              @available = DhanScalper::Support::Money.subtract(@available, amount_bd)
              @used = DhanScalper::Support::Money.add(@used, amount_bd)
            end
          elsif amount < 0
            # Handle negative amounts as credits (but only if there's used balance)
            if @used > 0
              credit_amount = DhanScalper::Support::Money.min(amount_bd.abs, @used)
              @used = DhanScalper::Support::Money.subtract(@used, credit_amount)
              @available = DhanScalper::Support::Money.add(@available, credit_amount)
            end
          end
        when :credit
          if amount > 0
            # For credit, only release used balance, don't add extra money
            if @used > 0
              credit_amount = DhanScalper::Support::Money.min(amount_bd, @used)
              @used = DhanScalper::Support::Money.subtract(@used, credit_amount)
              @available = DhanScalper::Support::Money.add(@available, credit_amount)
            end
          elsif amount < 0
            # Handle negative amounts as debits
            if DhanScalper::Support::Money.less_than?(@available, amount_bd.abs)
              # Not enough balance, use all available
              @used = DhanScalper::Support::Money.add(@used, @available)
              @available = DhanScalper::Support::Money.bd(0)
            else
              # Sufficient balance, proceed normally
              @available = DhanScalper::Support::Money.subtract(@available, amount_bd.abs)
              @used = DhanScalper::Support::Money.add(@used, amount_bd.abs)
            end
          end
        when :release_principal
          # Release principal from used balance and add it back to available balance
          @used = DhanScalper::Support::Money.subtract(@used, amount_bd)
          @available = DhanScalper::Support::Money.add(@available, amount_bd)
        end

        # Ensure used balance doesn't go negative
        @used = DhanScalper::Support::Money.max(@used, DhanScalper::Support::Money.bd(0))
        # Total balance should remain constant (starting balance + realized PnL)
        @total = DhanScalper::Support::Money.add(@starting_balance, @realized_pnl)

        # Save to Redis
        save_balance_to_redis

        DhanScalper::Support::Logger.debug(
          "Balance updated - available after: #{DhanScalper::Support::Money.dec(@available)}, " \
          "used after: #{DhanScalper::Support::Money.dec(@used)}, " \
          "total: #{DhanScalper::Support::Money.dec(@total)}",
          component: "PaperWallet",
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
          component: "PaperWallet",
        )

        total_cost = DhanScalper::Support::Money.add(principal_bd, fee_bd)
        DhanScalper::Support::Validations.validate_balance_sufficient(@available, total_cost)

        @available = DhanScalper::Support::Money.subtract(@available, total_cost)
        @used = DhanScalper::Support::Money.add(@used, total_cost)
        @total = DhanScalper::Support::Money.add(@available, @used)

        # Save to Redis
        save_balance_to_redis

        DhanScalper::Support::Logger.debug(
          "Buy debit completed - available: #{DhanScalper::Support::Money.dec(@available)}, " \
          "used: #{DhanScalper::Support::Money.dec(@used)}, " \
          "total: #{DhanScalper::Support::Money.dec(@total)}",
          component: "PaperWallet",
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
          component: "PaperWallet",
        )

        # Credit the actual cash received from the sale
        @available = DhanScalper::Support::Money.add(@available, net_bd)

        # Release the principal that was tied up in the position
        @used = DhanScalper::Support::Money.subtract(@used, released_bd)
        @used = DhanScalper::Support::Money.max(@used, DhanScalper::Support::Money.bd(0))

        # Total balance is available + used (no double counting)
        @total = DhanScalper::Support::Money.add(@available, @used)

        # Save to Redis
        save_balance_to_redis

        DhanScalper::Support::Logger.debug(
          "Sell credit completed - available: #{DhanScalper::Support::Money.dec(@available)}, " \
          "used: #{DhanScalper::Support::Money.dec(@used)}, " \
          "total: #{DhanScalper::Support::Money.dec(@total)}",
          component: "PaperWallet",
        )
        @total
      end

      def reset_balance(amount)
        @starting_balance = DhanScalper::Support::Money.bd(amount)
        @available = @starting_balance
        @used = DhanScalper::Support::Money.bd(0)
        @total = @starting_balance
        @realized_pnl = DhanScalper::Support::Money.bd(0)

        # Save to Redis
        save_balance_to_redis

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

        # Save to Redis
        save_balance_to_redis

        # NOTE: Realized PnL is tracked separately for reporting only
        # Cash flow is already reflected in available/used balance
        DhanScalper::Support::Logger.debug(
          "Added realized PnL: #{DhanScalper::Support::Money.dec(pnl)}, " \
          "realized_pnl now: #{DhanScalper::Support::Money.dec(@realized_pnl)}",
          component: "PaperWallet",
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
          component: "PaperWallet",
        )
        @total
      end

      # Clear used balance (for when positions are closed)
      def clear_used_balance
        @used = DhanScalper::Support::Money.bd(0)
        @total = DhanScalper::Support::Money.add(@available, @used)
      end

      private

        def generate_session_id
          "PAPER_#{Time.now.strftime("%Y%m%d")}"
        end

      def load_balance_from_redis
        key = "dhan_scalper:v1:balance:#{@session_id}"

        balance_data = @redis_store.redis.hgetall(key)

        if balance_data.empty?
          # Initialize with starting balance
          @available = @starting_balance
          @used = DhanScalper::Support::Money.bd(0)
          @total = @starting_balance
          @realized_pnl = DhanScalper::Support::Money.bd(0)

          # Save initial state
          save_balance_to_redis
        else
          # Load from Redis
          @available = DhanScalper::Support::Money.bd(balance_data["available"] || @starting_balance)
          @used = DhanScalper::Support::Money.bd(balance_data["used"] || 0)
          @total = DhanScalper::Support::Money.bd(balance_data["total"] || @starting_balance)
          @realized_pnl = DhanScalper::Support::Money.bd(balance_data["realized_pnl"] || 0)
        end

        DhanScalper::Support::Logger.debug(
          "Loaded balance from Redis - available: #{DhanScalper::Support::Money.dec(@available)}, " \
          "used: #{DhanScalper::Support::Money.dec(@used)}, " \
          "total: #{DhanScalper::Support::Money.dec(@total)}, " \
          "realized_pnl: #{DhanScalper::Support::Money.dec(@realized_pnl)}",
          component: "PaperWallet",
        )
      end

      def save_balance_to_redis
        key = "dhan_scalper:v1:balance:#{@session_id}"

        balance_data = {
          available: DhanScalper::Support::Money.dec(@available).to_s,
          used: DhanScalper::Support::Money.dec(@used).to_s,
          total: DhanScalper::Support::Money.dec(@total).to_s,
          realized_pnl: DhanScalper::Support::Money.dec(@realized_pnl).to_s,
          starting_balance: DhanScalper::Support::Money.dec(@starting_balance).to_s,
          last_updated: Time.now.iso8601,
        }

        @redis_store.redis.hset(key, balance_data)
        @redis_store.redis.expire(key, 86_400) # 24 hours TTL

        DhanScalper::Support::Logger.debug(
          "Saved balance to Redis - key: #{key}",
          component: "PaperWallet",
        )
      end

      def calculate_used_balance_from_positions
        # Try to get positions from session report first
        positions = get_positions_from_session_report
        return 0.0 if positions.nil? || positions.empty?

        # Calculate position values
        position_values = positions.sum do |position|
          quantity = position[:quantity] || position["quantity"] || 0
          entry_price = position[:entry_price] || position["entry_price"] || 0
          quantity * entry_price
        end

        # Calculate total fees (₹20 per order)
        fee_per_order = DhanScalper::Config.fee || 20.0
        total_fees = positions.length * fee_per_order

        total_used = position_values + total_fees

        DhanScalper::Support::Logger.debug(
          "Calculated used balance - positions: #{position_values}, fees: #{total_fees}, total: #{total_used}",
          component: "PaperWallet",
        )

        total_used.to_f
      end

      def get_positions_from_session_report
        # Find the latest session CSV file directly
        csv_files = Dir.glob(File.join("data/reports", "*.csv"))
        return [] if csv_files.empty?

        latest_file = csv_files.max_by { |f| File.mtime(f) }
        return [] unless latest_file

        # Parse the CSV file directly - this is a custom format, not standard CSV
        positions = []
        lines = File.readlines(latest_file)

        # Find the positions section
        positions_start = nil
        lines.each_with_index do |line, index|
          if line.strip == "POSITIONS"
            positions_start = index + 2 # Skip the header line
            break
          end
        end

        return [] unless positions_start

        # Parse position data
        (positions_start...lines.length).each do |i|
          line = lines[i].strip
          break if line.empty? || line.start_with?("TRADES")

          parts = line.split(",")
          next if parts.length < 8

          positions << {
            symbol: parts[0],
            option_type: parts[1],
            strike: parts[2],
            quantity: parts[3].to_i,
            entry_price: parts[4].to_f,
            current_price: parts[5].to_f,
            pnl: parts[6].to_f,
            created_at: parts[7],
          }
        end

        positions
      rescue StandardError => e
        DhanScalper::Support::Logger.debug(
          "Failed to get positions from session report: #{e.message}",
          component: "PaperWallet",
        )
        []
      end
    end
  end
end
