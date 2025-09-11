# frozen_string_literal: true

require "spec_helper"

RSpec.describe DhanScalper::Atomic do
  let(:redis_store) { double("RedisStore") }
  let(:balance_provider) { DhanScalper::BalanceProviders::PaperWallet.new(starting_balance: 100_000) }
  let(:position_tracker) { DhanScalper::Services::EnhancedPositionTracker.new }
  let(:security_id) { "TEST123" }
  let(:exchange_segment) { "NSE_EQ" }

  before do
    # Initialize Atomic with dependencies
    DhanScalper::Atomic.initialize(
      redis_store: redis_store,
      balance_provider: balance_provider,
      position_tracker: position_tracker
    )
  end

  after do
    # Reset class variable for clean tests
    DhanScalper::Atomic.instance_variable_set(:@atomic_ops, nil)
  end

  describe ".buy!" do
    it "delegates to atomic operations" do
      allow_any_instance_of(DhanScalper::Services::AtomicOperations).to receive(:buy!).and_return({
        success: true,
        order_id: "test-order-123"
      })

      result = DhanScalper::Atomic.buy!(
        exchange_segment: exchange_segment,
        security_id: security_id,
        quantity: 100,
        price: 100.0
      )

      expect(result[:success]).to be true
      expect(result[:order_id]).to eq("test-order-123")
    end

    it "passes all parameters correctly" do
      expect_any_instance_of(DhanScalper::Services::AtomicOperations).to receive(:buy!).with(
        exchange_segment: exchange_segment,
        security_id: security_id,
        side: "LONG",
        quantity: 100,
        price: 100.0,
        fee: 20
      ).and_return({ success: true })

      DhanScalper::Atomic.buy!(
        exchange_segment: exchange_segment,
        security_id: security_id,
        quantity: 100,
        price: 100.0,
        fee: 20
      )
    end
  end

  describe ".sell!" do
    it "delegates to atomic operations" do
      allow_any_instance_of(DhanScalper::Services::AtomicOperations).to receive(:sell!).and_return({
        success: true,
        sold_quantity: DhanScalper::Support::Money.bd(50)
      })

      result = DhanScalper::Atomic.sell!(
        exchange_segment: exchange_segment,
        security_id: security_id,
        quantity: 50,
        price: 120.0
      )

      expect(result[:success]).to be true
      expect(result[:sold_quantity]).to eq(DhanScalper::Support::Money.bd(50))
    end

    it "passes all parameters correctly" do
      expect_any_instance_of(DhanScalper::Services::AtomicOperations).to receive(:sell!).with(
        exchange_segment: exchange_segment,
        security_id: security_id,
        side: "LONG",
        quantity: 50,
        price: 120.0,
        fee: 20
      ).and_return({ success: true })

      DhanScalper::Atomic.sell!(
        exchange_segment: exchange_segment,
        security_id: security_id,
        quantity: 50,
        price: 120.0,
        fee: 20
      )
    end
  end

  describe ".balance" do
    it "delegates to atomic operations" do
      allow_any_instance_of(DhanScalper::Services::AtomicOperations).to receive(:get_balance).and_return({
        success: true,
        available: DhanScalper::Support::Money.bd(100_000),
        used: DhanScalper::Support::Money.bd(0),
        total: DhanScalper::Support::Money.bd(100_000)
      })

      result = DhanScalper::Atomic.balance

      expect(result[:success]).to be true
      expect(result[:available]).to eq(DhanScalper::Support::Money.bd(100_000))
    end
  end

  describe ".position" do
    it "delegates to atomic operations" do
      allow_any_instance_of(DhanScalper::Services::AtomicOperations).to receive(:get_position).and_return({
        success: true,
        position: {
          security_id: security_id,
          net_qty: DhanScalper::Support::Money.bd(100)
        }
      })

      result = DhanScalper::Atomic.position(
        exchange_segment: exchange_segment,
        security_id: security_id
      )

      expect(result[:success]).to be true
      expect(result[:position][:security_id]).to eq(security_id)
    end
  end

  describe ".available?" do
    it "returns true when initialized" do
      expect(DhanScalper::Atomic.available?).to be true
    end

    it "returns false when not initialized" do
      DhanScalper::Atomic.instance_variable_set(:@atomic_ops, nil)
      expect(DhanScalper::Atomic.available?).to be false
    end
  end

  describe "error handling" do
    it "raises error when not initialized" do
      DhanScalper::Atomic.instance_variable_set(:@atomic_ops, nil)

      expect {
        DhanScalper::Atomic.buy!(
          exchange_segment: exchange_segment,
          security_id: security_id,
          quantity: 100,
          price: 100.0
        )
      }.to raise_error("Atomic operations not initialized. Call Atomic.initialize first.")
    end
  end

  describe "integration with paper broker" do
    let(:broker) { DhanScalper::Brokers::PaperBroker.new(balance_provider: balance_provider) }

    it "can be used alongside paper broker" do
      # Initialize Atomic with broker's components
      DhanScalper::Atomic.initialize(
        redis_store: redis_store,
        balance_provider: broker.balance_provider,
        position_tracker: broker.position_tracker
      )

      # Both should work independently
      expect(DhanScalper::Atomic.available?).to be true
      expect(broker.balance_provider).to be_a(DhanScalper::BalanceProviders::PaperWallet)
    end
  end
end
