# frozen_string_literal: true

require "spec_helper"

RSpec.describe DhanScalper::Brokers::PaperBroker do
  let(:virtual_data_manager) { double("VirtualDataManager") }
  let(:balance_provider) { DhanScalper::BalanceProviders::PaperWallet.new(starting_balance: 100_000) }
  let(:broker) { described_class.new(virtual_data_manager: virtual_data_manager, balance_provider: balance_provider) }
  let(:redis_store) { double("RedisStore") }
  let(:security_id) { "TEST123" }
  let(:idempotency_key) { "test-order-123" }

  before do
    # Mock the virtual data manager
    allow(virtual_data_manager).to receive(:add_order)
    allow(virtual_data_manager).to receive(:add_position)
    allow(virtual_data_manager).to receive(:get_order_by_id)

    # Mock the tick cache
    allow(DhanScalper::TickCache).to receive(:ltp).and_return(100.0)

    # Mock Redis store
    allow(redis_store).to receive(:get_idempotency_key).and_return(nil)
    allow(redis_store).to receive(:store_idempotency_key)
  end

  describe "place_order! with idempotency" do
    context "when idempotency key is not provided" do
      it "places order normally without idempotency check" do
        result = broker.place_order!(
          symbol: "TEST",
          instrument_id: security_id,
          side: "BUY",
          quantity: 100,
          price: 100.0,
          redis_store: redis_store
        )

        expect(result[:success]).to be true
        expect(result[:idempotent]).to be_nil
        expect(redis_store).not_to have_received(:get_idempotency_key)
        expect(redis_store).not_to have_received(:store_idempotency_key)
      end
    end

    context "when idempotency key is provided but not found in Redis" do
      it "places order and stores idempotency key" do
        result = broker.place_order!(
          symbol: "TEST",
          instrument_id: security_id,
          side: "BUY",
          quantity: 100,
          price: 100.0,
          idempotency_key: idempotency_key,
          redis_store: redis_store
        )

        expect(result[:success]).to be true
        expect(result[:idempotent]).to be_nil
        expect(redis_store).to have_received(:get_idempotency_key).with(idempotency_key)
        expect(redis_store).to have_received(:store_idempotency_key).with(idempotency_key, result[:order_id])
      end
    end

    context "when idempotency key is found in Redis" do
      let(:existing_order_id) { "existing-order-456" }
      let(:existing_order) do
        {
          id: existing_order_id,
          security_id: security_id,
          side: "BUY",
          quantity: 100,
          avg_price: 100.0,
          timestamp: Time.now.iso8601,
          status: "COMPLETED"
        }
      end

      before do
        allow(redis_store).to receive(:get_idempotency_key).with(idempotency_key).and_return(existing_order_id)
        allow(virtual_data_manager).to receive(:get_order_by_id).with(existing_order_id).and_return(existing_order)
      end

      it "returns existing order without placing new one" do
        result = broker.place_order!(
          symbol: "TEST",
          instrument_id: security_id,
          side: "BUY",
          quantity: 100,
          price: 100.0,
          idempotency_key: idempotency_key,
          redis_store: redis_store
        )

        expect(result[:success]).to be true
        expect(result[:order_id]).to eq(existing_order_id)
        expect(result[:order]).to eq(existing_order)
        expect(result[:idempotent]).to be true
        expect(redis_store).to have_received(:get_idempotency_key).with(idempotency_key)
        expect(redis_store).not_to have_received(:store_idempotency_key)
      end

      it "maintains identical balance and positions" do
        # First call - should place order
        allow(redis_store).to receive(:get_idempotency_key).with(idempotency_key).and_return(nil)
        first_result = broker.place_order!(
          symbol: "TEST",
          instrument_id: security_id,
          side: "BUY",
          quantity: 100,
          price: 100.0,
          idempotency_key: idempotency_key,
          redis_store: redis_store
        )

        first_balance = broker.balance_provider.available_balance
        first_position = broker.position_tracker.get_position(exchange_segment: "NSE_EQ", security_id: security_id, side: "LONG")

        # Second call - should return existing order
        allow(redis_store).to receive(:get_idempotency_key).with(idempotency_key).and_return(first_result[:order_id])
        allow(virtual_data_manager).to receive(:get_order_by_id).with(first_result[:order_id]).and_return(existing_order)

        second_result = broker.place_order!(
          symbol: "TEST",
          instrument_id: security_id,
          side: "BUY",
          quantity: 100,
          price: 100.0,
          idempotency_key: idempotency_key,
          redis_store: redis_store
        )

        second_balance = broker.balance_provider.available_balance
        second_position = broker.position_tracker.get_position(exchange_segment: "NSE_EQ", security_id: security_id, side: "LONG")

        # Balance and positions should be identical
        expect(second_balance).to eq(first_balance)
        expect(second_position).to eq(first_position)
        expect(second_result[:idempotent]).to be true
      end
    end

    context "when idempotency key is found but order is missing" do
      let(:existing_order_id) { "missing-order-789" }

      before do
        allow(redis_store).to receive(:get_idempotency_key).with(idempotency_key).and_return(existing_order_id)
        allow(virtual_data_manager).to receive(:get_order_by_id).with(existing_order_id).and_return(nil)
      end

      it "places new order and updates idempotency key" do
        result = broker.place_order!(
          symbol: "TEST",
          instrument_id: security_id,
          side: "BUY",
          quantity: 100,
          price: 100.0,
          idempotency_key: idempotency_key,
          redis_store: redis_store
        )

        expect(result[:success]).to be true
        expect(result[:idempotent]).to be_nil
        expect(redis_store).to have_received(:get_idempotency_key).with(idempotency_key)
        expect(redis_store).to have_received(:store_idempotency_key).with(idempotency_key, result[:order_id])
      end
    end

    context "when order placement fails" do
      before do
        # Mock order placement failure
        allow(broker).to receive(:place_order).and_return({
          success: false,
          error: "Insufficient balance"
        })
      end

      it "does not store idempotency key" do
        result = broker.place_order!(
          symbol: "TEST",
          instrument_id: security_id,
          side: "BUY",
          quantity: 100,
          price: 100.0,
          idempotency_key: idempotency_key,
          redis_store: redis_store
        )

        expect(result[:success]).to be false
        expect(redis_store).not_to have_received(:store_idempotency_key)
      end
    end
  end

  describe "Redis store idempotency methods" do
    let(:redis_store_instance) { DhanScalper::Stores::RedisStore.new(namespace: "test") }
    let(:redis) { double("Redis") }

    before do
      redis_store_instance.instance_variable_set(:@redis, redis)
    end

    describe "#store_idempotency_key" do
      it "stores idempotency key with TTL" do
        expect(redis).to receive(:setex).with("test:idemp:key123", 86_400, "order456")

        redis_store_instance.store_idempotency_key("key123", "order456")
      end
    end

    describe "#get_idempotency_key" do
      it "retrieves idempotency key" do
        expect(redis).to receive(:get).with("test:idemp:key123").and_return("order456")

        result = redis_store_instance.get_idempotency_key("key123")
        expect(result).to eq("order456")
      end
    end

    describe "#has_idempotency_key?" do
      it "checks if idempotency key exists" do
        expect(redis).to receive(:exists?).with("test:idemp:key123").and_return(true)

        result = redis_store_instance.has_idempotency_key?("key123")
        expect(result).to be true
      end
    end

    describe "#delete_idempotency_key" do
      it "deletes idempotency key" do
        expect(redis).to receive(:del).with("test:idemp:key123")

        redis_store_instance.delete_idempotency_key("key123")
      end
    end
  end

  describe "integration test with real Redis store" do
    let(:redis_store_instance) { DhanScalper::Stores::RedisStore.new(namespace: "test_idempotency") }
    let(:broker_with_redis) { described_class.new(virtual_data_manager: virtual_data_manager, balance_provider: balance_provider) }
    let(:redis) { double("Redis") }

    before do
      # Mock Redis connection
      allow(redis_store_instance).to receive(:connect)
      allow(redis_store_instance).to receive(:disconnect)
      redis_store_instance.instance_variable_set(:@redis, redis)

      # Mock Redis methods
      allow(redis).to receive(:get).and_return(nil)
      allow(redis).to receive(:setex)
    end

    it "ensures single order in ledger with identical balance/positions" do
      # Mock order data
      order_data = {
        id: "test-order-123",
        security_id: security_id,
        side: "BUY",
        quantity: 100,
        avg_price: 100.0,
        timestamp: Time.now.iso8601,
        status: "COMPLETED"
      }

      allow(virtual_data_manager).to receive(:get_order_by_id).with("test-order-123").and_return(order_data)

      # First call - Redis returns nil (no existing key)
      allow(redis).to receive(:get).with("test_idempotency:idemp:test-key-123").and_return(nil)

      first_result = broker_with_redis.place_order!(
        symbol: "TEST",
        instrument_id: security_id,
        side: "BUY",
        quantity: 100,
        price: 100.0,
        idempotency_key: "test-key-123",
        redis_store: redis_store_instance
      )

      first_balance = broker_with_redis.balance_provider.available_balance
      first_position = broker_with_redis.position_tracker.get_position(exchange_segment: "NSE_EQ", security_id: security_id, side: "LONG")

      # Second call - Redis returns the order ID from first call
      allow(redis).to receive(:get).with("test_idempotency:idemp:test-key-123").and_return(first_result[:order_id])
      allow(virtual_data_manager).to receive(:get_order_by_id).with(first_result[:order_id]).and_return(order_data)

      second_result = broker_with_redis.place_order!(
        symbol: "TEST",
        instrument_id: security_id,
        side: "BUY",
        quantity: 100,
        price: 100.0,
        idempotency_key: "test-key-123",
        redis_store: redis_store_instance
      )

      second_balance = broker_with_redis.balance_provider.available_balance
      second_position = broker_with_redis.position_tracker.get_position(exchange_segment: "NSE_EQ", security_id: security_id, side: "LONG")

      # Verify idempotency
      expect(second_result[:idempotent]).to be true
      expect(second_balance).to eq(first_balance)
      expect(second_position).to eq(first_position)
    end
  end
end
