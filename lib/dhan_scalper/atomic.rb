# frozen_string_literal: true

require_relative "services/atomic_operations"

module DhanScalper
  # Clean Ruby facade for atomic operations
  class Atomic
    class << self
      # Initialize atomic operations with required dependencies
      def initialize(redis_store:, balance_provider:, position_tracker:, logger: Logger.new($stdout))
        @atomic_ops = Services::AtomicOperations.new(
          redis_store: redis_store,
          balance_provider: balance_provider,
          position_tracker: position_tracker,
          logger: logger
        )
      end

      # Atomic buy operation
      def buy!(exchange_segment:, security_id:, side: "LONG", quantity:, price:, fee: nil)
        ensure_initialized!
        @atomic_ops.buy!(
          exchange_segment: exchange_segment,
          security_id: security_id,
          side: side,
          quantity: quantity,
          price: price,
          fee: fee
        )
      end

      # Atomic sell operation
      def sell!(exchange_segment:, security_id:, side: "LONG", quantity:, price:, fee: nil)
        ensure_initialized!
        @atomic_ops.sell!(
          exchange_segment: exchange_segment,
          security_id: security_id,
          side: side,
          quantity: quantity,
          price: price,
          fee: fee
        )
      end

      # Get current balance atomically
      def balance
        ensure_initialized!
        @atomic_ops.get_balance
      end

      # Get position atomically
      def position(exchange_segment:, security_id:, side: "LONG")
        ensure_initialized!
        @atomic_ops.get_position(
          exchange_segment: exchange_segment,
          security_id: security_id,
          side: side
        )
      end

      # Check if atomic operations are available
      def available?
        !@atomic_ops.nil?
      end

      private

      def ensure_initialized!
        raise "Atomic operations not initialized. Call Atomic.initialize first." unless @atomic_ops
      end
    end
  end
end
