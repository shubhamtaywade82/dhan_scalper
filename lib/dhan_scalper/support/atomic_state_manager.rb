# frozen_string_literal: true

require "redis"
require "json"
require_relative "money"
require_relative "logger"

module DhanScalper
  module Support
    class AtomicStateManager
      def initialize(redis_url: nil, namespace: "dhan_scalper:state")
        @redis = Redis.new(url: redis_url) if redis_url
        @redis ||= Redis.new
        @namespace = namespace
        @mutex = Mutex.new
      end

      # Atomic balance operations
      def atomic_balance_update(operation)
        @mutex.synchronize do
          @redis.multi do |_multi|
            # Get current state
            current_state = get_balance_state

            # Execute the operation in a block
            new_state = yield(current_state.dup)

            # Validate the new state
            validate_balance_state(new_state)

            # Update state atomically
            set_balance_state(new_state)

            Logger.debug(
              "Atomic balance update: #{operation} - " \
              "available: #{Money.dec(new_state[:available])}, " \
              "used: #{Money.dec(new_state[:used])}, " \
              "realized_pnl: #{Money.dec(new_state[:realized_pnl])}",
              component: "AtomicStateManager",
            )

            new_state
          end
        end
      rescue StandardError => e
        Logger.error("Atomic balance update failed: #{e.message}", component: "AtomicStateManager")
        raise
      end

      # Atomic position operations
      def atomic_position_update(operation)
        @mutex.synchronize do
          @redis.multi do |_multi|
            # Get current positions
            current_positions = get_positions_state

            # Execute the operation in a block
            new_positions = yield(current_positions.dup)

            # Validate the new positions
            validate_positions_state(new_positions)

            # Update positions atomically
            set_positions_state(new_positions)

            Logger.debug(
              "Atomic position update: #{operation} - " \
              "positions count: #{new_positions.size}",
              component: "AtomicStateManager",
            )

            new_positions
          end
        end
      rescue StandardError => e
        Logger.error("Atomic position update failed: #{e.message}", component: "AtomicStateManager")
        raise
      end

      # Get current balance state
      def get_balance_state
        state_data = @redis.hgetall("#{@namespace}:balance")

        if state_data.empty?
          # Initialize with default state
          default_state = {
            available: Money.bd(200_000.0),
            used: Money.bd(0),
            realized_pnl: Money.bd(0),
            total: Money.bd(200_000.0),
            starting_balance: Money.bd(200_000.0),
          }
          set_balance_state(default_state)
          return default_state
        end

        {
          available: Money.bd(state_data["available"] || "0"),
          used: Money.bd(state_data["used"] || "0"),
          realized_pnl: Money.bd(state_data["realized_pnl"] || "0"),
          total: Money.bd(state_data["total"] || "0"),
          starting_balance: Money.bd(state_data["starting_balance"] || "200000"),
        }
      end

      # Set balance state atomically
      def set_balance_state(state)
        @redis.hmset(
          "#{@namespace}:balance",
          "available", Money.dec(state[:available]),
          "used", Money.dec(state[:used]),
          "realized_pnl", Money.dec(state[:realized_pnl]),
          "total", Money.dec(state[:total]),
          "starting_balance", Money.dec(state[:starting_balance]),
          "updated_at", Time.now.to_i
        )
      end

      # Get current positions state
      def get_positions_state
        positions_data = @redis.hgetall("#{@namespace}:positions")

        positions_data.transform_values do |position_json|
          position_data = JSON.parse(position_json, symbolize_names: true)
          # Convert string values back to BigDecimal
          position_data.transform_values do |value|
            if value.is_a?(String) && value.match?(/^\d+\.?\d*$/)
              Money.bd(value)
            else
              value
            end
          end
        end
      end

      # Set positions state atomically
      def set_positions_state(positions)
        # Clear existing positions
        @redis.del("#{@namespace}:positions")

        return if positions.empty?

        # Set new positions
        positions_data = positions.transform_values do |position|
          # Convert BigDecimal values to strings for JSON serialization
          serializable_position = position.transform_values do |value|
            if value.is_a?(BigDecimal)
              Money.dec(value)
            else
              value
            end
          end
          JSON.generate(serializable_position)
        end

        @redis.hmset("#{@namespace}:positions", *positions_data.flatten)
      end

      # Atomic balance debit operation
      def atomic_debit(amount, fee: 0)
        atomic_balance_update("debit") do |state|
          amount_bd = Money.bd(amount)
          fee_bd = Money.bd(fee)
          total_cost = Money.add(amount_bd, fee_bd)

          # Validate sufficient funds
          if Money.less_than?(state[:available], total_cost)
            raise InsufficientFunds,
                  "Insufficient funds: required #{Money.dec(total_cost)}, " \
                  "available #{Money.dec(state[:available])}"
          end

          # Update state
          state[:available] = Money.subtract(state[:available], total_cost)
          state[:used] = Money.add(state[:used], total_cost)
          state[:total] = Money.add(state[:available], state[:used])

          state
        end
      end

      # Atomic balance credit operation
      def atomic_credit(amount)
        atomic_balance_update("credit") do |state|
          amount_bd = Money.bd(amount)

          state[:available] = Money.add(state[:available], amount_bd)
          state[:total] = Money.add(state[:available], state[:used])

          state
        end
      end

      # Atomic position update
      def atomic_position_update(security_id, position_data)
        atomic_position_update("position_update") do |positions|
          positions[security_id] = position_data
          positions
        end
      end

      # Atomic position removal
      def atomic_position_remove(security_id)
        atomic_position_update("position_remove") do |positions|
          positions.delete(security_id)
          positions
        end
      end

      # Get balance snapshot (read-only)
      def balance_snapshot
        get_balance_state
      end

      # Get positions snapshot (read-only)
      def positions_snapshot
        get_positions_state
      end

      # Reset all state
      def reset_state
        @mutex.synchronize do
          @redis.del("#{@namespace}:balance")
          @redis.del("#{@namespace}:positions")

          # Initialize with default state
          default_state = {
            available: Money.bd(200_000.0),
            used: Money.bd(0),
            realized_pnl: Money.bd(0),
            total: Money.bd(200_000.0),
            starting_balance: Money.bd(200_000.0),
          }
          set_balance_state(default_state)

          Logger.info("State reset completed", component: "AtomicStateManager")
        end
      end

      private

      def validate_balance_state(state)
        # Ensure all required fields are present
        required_fields = %i[available used realized_pnl total starting_balance]
        missing_fields = required_fields - state.keys
        raise ArgumentError, "Missing required fields: #{missing_fields}" unless missing_fields.empty?

        # Ensure all values are BigDecimal
        state.each do |key, value|
          unless value.is_a?(BigDecimal)
            raise ArgumentError, "Field #{key} must be BigDecimal, got #{value.class}"
          end
        end

        # Validate non-negative values
        %i[available used total starting_balance].each do |field|
          if Money.negative?(state[field])
            raise ArgumentError, "Field #{field} cannot be negative: #{Money.dec(state[field])}"
          end
        end

        # Validate total calculation
        expected_total = Money.add(state[:available], state[:used])
        return if Money.equal?(state[:total], expected_total)

        raise ArgumentError,
              "Total calculation mismatch: expected #{Money.dec(expected_total)}, " \
              "got #{Money.dec(state[:total])}"
      end

      def validate_positions_state(positions)
        # Validate each position has required fields
        positions.each do |security_id, position|
          required_fields = %i[security_id exchange_segment side net_qty buy_avg]
          missing_fields = required_fields - position.keys
          unless missing_fields.empty?
            raise ArgumentError,
                  "Position #{security_id} missing required fields: #{missing_fields}"
          end
        end
      end
    end
  end
end
