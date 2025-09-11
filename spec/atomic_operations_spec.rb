# frozen_string_literal: true

require "spec_helper"

RSpec.describe DhanScalper::Services::AtomicOperations do
  let(:redis_store) { double("RedisStore") }
  let(:balance_provider) { DhanScalper::BalanceProviders::PaperWallet.new(starting_balance: 100_000) }
  let(:position_tracker) { DhanScalper::Services::EnhancedPositionTracker.new }
  let(:atomic_ops) { described_class.new(redis_store: redis_store, balance_provider: balance_provider, position_tracker: position_tracker) }
  let(:redis) { double("Redis") }
  let(:security_id) { "TEST123" }
  let(:exchange_segment) { "NSE_EQ" }

  before do
    allow(redis_store).to receive(:redis).and_return(redis)
    allow(redis_store).to receive(:namespace).and_return("test_atomic")

    # Mock Redis operations
    allow(redis).to receive(:multi).and_yield(redis)
    allow(redis).to receive(:eval).and_return(["ok", "100000.0"])
    allow(redis).to receive(:hgetall).and_return({
      "available" => "100000.0",
      "used" => "0.0",
      "total" => "100000.0"
    })
    allow(redis).to receive(:hincrbyfloat).and_return("100000.0")
    allow(redis).to receive(:hset).and_return("1")
    allow(redis).to receive(:expire).and_return("1")
  end

  describe "#buy!" do
    it "executes atomic buy operation successfully" do
      result = atomic_ops.buy!(
        exchange_segment: exchange_segment,
        security_id: security_id,
        side: "LONG",
        quantity: 100,
        price: 100.0,
        fee: 20
      )

      expect(result[:success]).to be true
      expect(redis).to have_received(:multi)
    end

    it "fails when insufficient balance" do
      # Set balance to 0
      balance_provider.instance_variable_set(:@available, DhanScalper::Support::Money.bd(0))

      result = atomic_ops.buy!(
        exchange_segment: exchange_segment,
        security_id: security_id,
        side: "LONG",
        quantity: 100,
        price: 100.0,
        fee: 20
      )

      expect(result[:success]).to be false
      expect(result[:error]).to include("Insufficient balance")
    end
  end

  describe "#sell!" do
    before do
      # Create a position first
      position_tracker.add_position(
        exchange_segment: exchange_segment,
        security_id: security_id,
        side: "LONG",
        quantity: 100,
        price: 100.0,
        fee: 20
      )
    end

    it "executes atomic sell operation successfully" do
      result = atomic_ops.sell!(
        exchange_segment: exchange_segment,
        security_id: security_id,
        side: "LONG",
        quantity: 50,
        price: 120.0,
        fee: 20
      )

      expect(result[:success]).to be true
      expect(result[:sold_quantity]).to eq(DhanScalper::Support::Money.bd(50))
      expect(redis).to have_received(:multi)
    end

    it "fails when no position exists" do
      result = atomic_ops.sell!(
        exchange_segment: exchange_segment,
        security_id: "NONEXISTENT",
        side: "LONG",
        quantity: 50,
        price: 120.0,
        fee: 20
      )

      expect(result[:success]).to be false
      expect(result[:error]).to include("No position found")
    end

    it "only sells available quantity" do
      result = atomic_ops.sell!(
        exchange_segment: exchange_segment,
        security_id: security_id,
        side: "LONG",
        quantity: 150, # More than available
        price: 120.0,
        fee: 20
      )

      expect(result[:success]).to be true
      expect(result[:sold_quantity]).to eq(DhanScalper::Support::Money.bd(100)) # Only available quantity
    end
  end

  describe "concurrency tests" do
    let(:threads) { [] }
    let(:results) { [] }
    let(:mutex) { Mutex.new }

    before do
      # Create initial position
      position_tracker.add_position(
        exchange_segment: exchange_segment,
        security_id: security_id,
        side: "LONG",
        quantity: 200,
        price: 100.0,
        fee: 20
      )
    end

    it "handles concurrent sell operations atomically" do
      # Simulate two concurrent sell operations
      2.times do |i|
        threads << Thread.new do
          result = atomic_ops.sell!(
            exchange_segment: exchange_segment,
            security_id: security_id,
            side: "LONG",
            quantity: 100,
            price: 120.0,
            fee: 20
          )

          mutex.synchronize do
            results << result
          end
        end
      end

      # Wait for all threads to complete
      threads.each(&:join)

      # Verify results
      expect(results.length).to eq(2)

      # Both operations should succeed
      results.each do |result|
        expect(result[:success]).to be true
      end

      # Total sold quantity should not exceed available
      total_sold = results.sum { |r| DhanScalper::Support::Money.dec(r[:sold_quantity]) }
      expect(total_sold).to be <= 200.0
    end

    it "handles concurrent buy operations atomically" do
      # Simulate two concurrent buy operations
      2.times do |i|
        threads << Thread.new do
          result = atomic_ops.buy!(
            exchange_segment: exchange_segment,
            security_id: security_id,
            side: "LONG",
            quantity: 50,
            price: 100.0,
            fee: 20
          )

          mutex.synchronize do
            results << result
          end
        end
      end

      # Wait for all threads to complete
      threads.each(&:join)

      # Verify results
      expect(results.length).to eq(2)

      # Both operations should succeed
      results.each do |result|
        expect(result[:success]).to be true
      end

      # Balance should be consistent
      final_balance = balance_provider.available_balance
      expect(final_balance).to be > DhanScalper::Support::Money.bd(0)
    end

    it "prevents negative quantities under concurrent access" do
      # Create position with limited quantity
      position_tracker.add_position(
        exchange_segment: exchange_segment,
        security_id: security_id,
        side: "LONG",
        quantity: 100,
        price: 100.0,
        fee: 20
      )

      # Simulate multiple concurrent sell operations trying to sell more than available
      3.times do |i|
        threads << Thread.new do
          result = atomic_ops.sell!(
            exchange_segment: exchange_segment,
            security_id: security_id,
            side: "LONG",
            quantity: 60, # Each trying to sell 60, but only 100 total available
            price: 120.0,
            fee: 20
          )

          mutex.synchronize do
            results << result
          end
        end
      end

      # Wait for all threads to complete
      threads.each(&:join)

      # Verify no negative quantities
      total_sold = results.select { |r| r[:success] }.sum { |r| DhanScalper::Support::Money.dec(r[:sold_quantity]) }
      expect(total_sold).to be <= 100.0

      # At least one operation should succeed
      successful_operations = results.count { |r| r[:success] }
      expect(successful_operations).to be >= 1
    end

    it "maintains consistent final state under high concurrency" do
      # Create initial state
      initial_balance = balance_provider.available_balance
      initial_position = position_tracker.get_position(
        exchange_segment: exchange_segment,
        security_id: security_id,
        side: "LONG"
      )

      # Simulate mixed buy/sell operations
      10.times do |i|
        threads << Thread.new do
          if i.even?
            # Buy operation
            result = atomic_ops.buy!(
              exchange_segment: exchange_segment,
              security_id: security_id,
              side: "LONG",
              quantity: 10,
              price: 100.0,
              fee: 20
            )
          else
            # Sell operation
            result = atomic_ops.sell!(
              exchange_segment: exchange_segment,
              security_id: security_id,
              side: "LONG",
              quantity: 10,
              price: 120.0,
              fee: 20
            )
          end

          mutex.synchronize do
            results << result
          end
        end
      end

      # Wait for all threads to complete
      threads.each(&:join)

      # Verify final state consistency
      final_balance = balance_provider.available_balance
      final_position = position_tracker.get_position(
        exchange_segment: exchange_segment,
        security_id: security_id,
        side: "LONG"
      )

      # Balance should be reasonable (not negative, not infinite)
      expect(final_balance).to be > DhanScalper::Support::Money.bd(0)
      expect(final_balance).to be < initial_balance * 2

      # Position should exist and be consistent
      expect(final_position).not_to be_nil
      expect(final_position[:net_qty]).to be >= DhanScalper::Support::Money.bd(0)
    end
  end

  describe "Redis MULTI/EXEC behavior" do
    it "rolls back on Redis errors" do
      allow(redis).to receive(:multi).and_raise(StandardError, "Redis connection lost")

      result = atomic_ops.buy!(
        exchange_segment: exchange_segment,
        security_id: security_id,
        side: "LONG",
        quantity: 100,
        price: 100.0,
        fee: 20
      )

      expect(result[:success]).to be false
      expect(result[:error]).to include("Redis connection lost")
    end

    it "handles Lua script errors gracefully" do
      allow(redis).to receive(:eval).and_return(["err", "Insufficient balance"])

      result = atomic_ops.buy!(
        exchange_segment: exchange_segment,
        security_id: security_id,
        side: "LONG",
        quantity: 100,
        price: 100.0,
        fee: 20
      )

      expect(result[:success]).to be false
      expect(result[:error]).to include("Insufficient balance")
    end
  end
end
