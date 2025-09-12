# frozen_string_literal: true

require "spec_helper"

RSpec.describe DhanScalper::Brokers::PaperBroker do
  let(:balance_provider) { DhanScalper::BalanceProviders::PaperWallet.new(starting_balance: 100_000.0) }
  let(:broker) { described_class.new(balance_provider: balance_provider) }
  let(:security_id) { "TEST123" }
  let(:segment) { "NSE_EQ" }

  before do
    # Mock TickCache to return a valid price
    allow(DhanScalper::TickCache).to receive(:ltp).with(segment, security_id).and_return(100.0)
  end

  describe "buy_market validation" do
    context "when balance is insufficient" do
      before do
        # Set a very low balance
        balance_provider.instance_variable_set(:@available, DhanScalper::Support::Money.bd(50.0))
      end

      it "returns validation error without changing balance or positions" do
        initial_balance = balance_provider.available_balance
        initial_positions = broker.position_tracker.get_positions

        result = broker.buy_market(
          segment: segment,
          security_id: security_id,
          quantity: 100,
          charge_per_order: 20
        )

        expect(result).to be_a(Hash)
        expect(result[:success]).to be false
        expect(result[:error]).to eq("INSUFFICIENT_BALANCE")
        expect(result[:error_message]).to include("Insufficient balance")
        expect(result[:error_message]).to include("Need ₹")
        expect(result[:error_message]).to include("have ₹")

        # Verify no side effects
        expect(balance_provider.available_balance).to eq(initial_balance)
        expect(broker.position_tracker.get_positions).to eq(initial_positions)
      end

      it "includes detailed cost breakdown in error message" do
        result = broker.buy_market(
          segment: segment,
          security_id: security_id,
          quantity: 100,
          charge_per_order: 20
        )

        # Total cost should be (100 * 100) + 20 = 10020
        expect(result[:error_message]).to include("10020")
        expect(result[:error_message]).to include("50")
      end
    end

    context "when price is invalid" do
      before do
        allow(DhanScalper::TickCache).to receive(:ltp).with(segment, security_id).and_return(nil)
      end

      it "returns validation error without changing state" do
        initial_balance = balance_provider.available_balance
        initial_positions = broker.position_tracker.get_positions

        result = broker.buy_market(
          segment: segment,
          security_id: security_id,
          quantity: 100,
          charge_per_order: 20
        )

        expect(result).to be_a(Hash)
        expect(result[:success]).to be false
        expect(result[:error]).to eq("INVALID_PRICE")
        expect(result[:error_message]).to include("No valid price available")

        # Verify no side effects
        expect(balance_provider.available_balance).to eq(initial_balance)
        expect(broker.position_tracker.get_positions).to eq(initial_positions)
      end
    end

    context "when price is zero" do
      before do
        allow(DhanScalper::TickCache).to receive(:ltp).with(segment, security_id).and_return(0.0)
      end

      it "returns validation error without changing state" do
        initial_balance = balance_provider.available_balance
        initial_positions = broker.position_tracker.get_positions

        result = broker.buy_market(
          segment: segment,
          security_id: security_id,
          quantity: 100,
          charge_per_order: 20
        )

        expect(result).to be_a(Hash)
        expect(result[:success]).to be false
        expect(result[:error]).to eq("INVALID_PRICE")
        expect(result[:error_message]).to include("No valid price available")

        # Verify no side effects
        expect(balance_provider.available_balance).to eq(initial_balance)
        expect(broker.position_tracker.get_positions).to eq(initial_positions)
      end
    end

    context "when balance is sufficient" do
      it "executes the order successfully" do
        result = broker.buy_market(
          segment: segment,
          security_id: security_id,
          quantity: 100,
          charge_per_order: 20
        )

        expect(result).to be_a(DhanScalper::Brokers::Order)
        expect(result.side).to eq("BUY")
        expect(result.qty).to eq(100)
        expect(result.avg_price).to eq(100.0)
      end
    end
  end

  describe "sell_market validation" do
    context "when no position exists" do
      it "returns validation error without changing state" do
        initial_balance = balance_provider.available_balance
        initial_positions = broker.position_tracker.get_positions

        result = broker.sell_market(
          segment: segment,
          security_id: security_id,
          quantity: 100,
          charge_per_order: 20
        )

        expect(result).to be_a(Hash)
        expect(result[:success]).to be false
        expect(result[:error]).to eq("INSUFFICIENT_POSITION")
        expect(result[:error_message]).to include("Insufficient position")
        expect(result[:error_message]).to include("Trying to sell")
        expect(result[:error_message]).to include("have 0")

        # Verify no side effects
        expect(balance_provider.available_balance).to eq(initial_balance)
        expect(broker.position_tracker.get_positions).to eq(initial_positions)
      end
    end

    context "when position quantity is insufficient" do
      before do
        # Create a position with limited quantity
        broker.position_tracker.add_position(
          exchange_segment: segment,
          security_id: security_id,
          side: "LONG",
          quantity: 50, # Less than what we're trying to sell
          price: 100.0,
          fee: 20
        )
      end

      it "returns validation error without changing state" do
        initial_balance = balance_provider.available_balance
        initial_positions = broker.position_tracker.get_positions

        result = broker.sell_market(
          segment: segment,
          security_id: security_id,
          quantity: 100, # More than available
          charge_per_order: 20
        )

        expect(result).to be_a(Hash)
        expect(result[:success]).to be false
        expect(result[:error]).to eq("INSUFFICIENT_POSITION")
        expect(result[:error_message]).to include("Insufficient position")
        expect(result[:error_message]).to include("Trying to sell 100")
        expect(result[:error_message]).to include("have 50")

        # Verify no side effects
        expect(balance_provider.available_balance).to eq(initial_balance)
        expect(broker.position_tracker.get_positions).to eq(initial_positions)
      end
    end

    context "when price is invalid" do
      before do
        # Create a position first
        broker.position_tracker.add_position(
          exchange_segment: segment,
          security_id: security_id,
          side: "LONG",
          quantity: 100,
          price: 100.0,
          fee: 20
        )
        allow(DhanScalper::TickCache).to receive(:ltp).with(segment, security_id).and_return(nil)
      end

      it "returns validation error without changing state" do
        initial_balance = balance_provider.available_balance
        initial_positions = broker.position_tracker.get_positions

        result = broker.sell_market(
          segment: segment,
          security_id: security_id,
          quantity: 50,
          charge_per_order: 20
        )

        expect(result).to be_a(Hash)
        expect(result[:success]).to be false
        expect(result[:error]).to eq("INVALID_PRICE")
        expect(result[:error_message]).to include("No valid price available")

        # Verify no side effects
        expect(balance_provider.available_balance).to eq(initial_balance)
        expect(broker.position_tracker.get_positions).to eq(initial_positions)
      end
    end

    context "when position is sufficient" do
      before do
        # Create a position with sufficient quantity
        broker.position_tracker.add_position(
          exchange_segment: segment,
          security_id: security_id,
          side: "LONG",
          quantity: 100,
          price: 100.0,
          fee: 20
        )
      end

      it "executes the order successfully" do
        result = broker.sell_market(
          segment: segment,
          security_id: security_id,
          quantity: 50,
          charge_per_order: 20
        )

        expect(result).to be_a(DhanScalper::Brokers::Order)
        expect(result.side).to eq("SELL")
        expect(result.qty).to eq(50)
        expect(result.avg_price).to eq(100.0)
      end
    end
  end

  describe "place_order validation" do
    context "when buy order validation fails" do
      before do
        balance_provider.instance_variable_set(:@available, DhanScalper::Support::Money.bd(50.0))
      end

      it "returns validation error from buy_market" do
        result = broker.place_order(
          symbol: "TEST",
          instrument_id: security_id,
          side: "BUY",
          quantity: 100,
          price: 100.0
        )

        expect(result).to be_a(Hash)
        expect(result[:success]).to be false
        expect(result[:error]).to eq("INSUFFICIENT_BALANCE")
        expect(result[:error_message]).to include("Insufficient balance")
      end
    end

    context "when sell order validation fails" do
      it "returns validation error from sell_market" do
        result = broker.place_order(
          symbol: "TEST",
          instrument_id: security_id,
          side: "SELL",
          quantity: 100,
          price: 100.0
        )

        expect(result).to be_a(Hash)
        expect(result[:success]).to be false
        expect(result[:error]).to eq("INSUFFICIENT_POSITION")
        expect(result[:error_message]).to include("Insufficient position")
      end
    end
  end

  describe "state preservation during validation failures" do
    it "preserves balance and positions when buy validation fails" do
      # Set up initial state
      balance_provider.instance_variable_set(:@available, DhanScalper::Support::Money.bd(50.0))
      initial_balance = balance_provider.available_balance
      initial_used = balance_provider.used_balance
      initial_positions = broker.position_tracker.get_positions.dup

      # Attempt oversized buy order
      broker.buy_market(
        segment: segment,
        security_id: security_id,
        quantity: 100,
        charge_per_order: 20
      )

      # Verify state is unchanged
      expect(balance_provider.available_balance).to eq(initial_balance)
      expect(balance_provider.used_balance).to eq(initial_used)
      expect(broker.position_tracker.get_positions).to eq(initial_positions)
    end

    it "preserves balance and positions when sell validation fails" do
      # Set up initial state
      initial_balance = balance_provider.available_balance
      initial_used = balance_provider.used_balance
      initial_positions = broker.position_tracker.get_positions.dup

      # Attempt sell without position
      broker.sell_market(
        segment: segment,
        security_id: security_id,
        quantity: 100,
        charge_per_order: 20
      )

      # Verify state is unchanged
      expect(balance_provider.available_balance).to eq(initial_balance)
      expect(balance_provider.used_balance).to eq(initial_used)
      expect(broker.position_tracker.get_positions).to eq(initial_positions)
    end
  end

  describe "error message clarity" do
    it "provides specific error codes for different validation failures" do
      # Test invalid price
      allow(DhanScalper::TickCache).to receive(:ltp).with(segment, security_id).and_return(nil)
      result = broker.buy_market(segment: segment, security_id: security_id, quantity: 100)
      expect(result[:error]).to eq("INVALID_PRICE")

      # Test insufficient balance
      allow(DhanScalper::TickCache).to receive(:ltp).with(segment, security_id).and_return(100.0)
      balance_provider.instance_variable_set(:@available, DhanScalper::Support::Money.bd(50.0))
      result = broker.buy_market(segment: segment, security_id: security_id, quantity: 100)
      expect(result[:error]).to eq("INSUFFICIENT_BALANCE")

      # Test insufficient position
      allow(DhanScalper::TickCache).to receive(:ltp).with(segment, security_id).and_return(100.0)
      balance_provider.instance_variable_set(:@available, DhanScalper::Support::Money.bd(100_000.0))
      result = broker.sell_market(segment: segment, security_id: security_id, quantity: 100)
      expect(result[:error]).to eq("INSUFFICIENT_POSITION")
    end

    it "includes relevant quantities in error messages" do
      # Test balance error includes needed vs available amounts
      balance_provider.instance_variable_set(:@available, DhanScalper::Support::Money.bd(50.0))
      result = broker.buy_market(segment: segment, security_id: security_id, quantity: 100, charge_per_order: 20)
      expect(result[:error_message]).to match(/Need ₹\d+\.\d+, have ₹50\.0/)

      # Test position error includes trying to sell vs available
      result = broker.sell_market(segment: segment, security_id: security_id, quantity: 100, charge_per_order: 20)
      expect(result[:error_message]).to match(/Trying to sell 100\.0, have 0\.0/)
    end
  end
end
