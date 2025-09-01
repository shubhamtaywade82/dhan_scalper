# frozen_string_literal: true

require "spec_helper"

RSpec.describe DhanScalper::Brokers::PaperBroker do
  let(:mock_balance_provider) { double("BalanceProvider") }
  let(:paper_broker) { described_class.new(balance_provider: mock_balance_provider) }

  before do
    # Mock balance provider methods
    allow(mock_balance_provider).to receive(:available_balance).and_return(100_000.0)
    allow(mock_balance_provider).to receive(:update_balance)
  end

  describe "#initialize" do
    it "sets the balance provider" do
      expect(paper_broker.instance_variable_get(:@balance_provider)).to eq(mock_balance_provider)
    end

    it "initializes empty orders and positions" do
      expect(paper_broker.instance_variable_get(:@orders)).to eq([])
      expect(paper_broker.instance_variable_get(:@positions)).to eq([])
    end
  end

  describe "#buy" do
    let(:symbol) { "NIFTY" }
    let(:quantity) { 100 }
    let(:price) { 50.0 }

    context "when sufficient balance is available" do
      before do
        allow(mock_balance_provider).to receive(:available_balance).and_return(100_000.0)
      end

      it "creates a buy order successfully" do
        result = paper_broker.buy(symbol, quantity, price)

        expect(result[:status]).to eq("SUCCESS")
        expect(result[:action]).to eq("BUY")
        expect(result[:symbol]).to eq(symbol)
        expect(result[:quantity]).to eq(quantity)
        expect(result[:price]).to eq(price)
        expect(result[:order_id]).to match(/PAPER_ORDER_\d+/)
      end

      it "adds the order to orders list" do
        paper_broker.buy(symbol, quantity, price)

        orders = paper_broker.instance_variable_get(:@orders)
        expect(orders.length).to eq(1)
        expect(orders.first[:action]).to eq("BUY")
        expect(orders.first[:symbol]).to eq(symbol)
      end

      it "updates balance provider with debit" do
        paper_broker.buy(symbol, quantity, price)

        total_cost = quantity * price
        expect(mock_balance_provider).to have_received(:update_balance).with(total_cost, type: :debit)
      end

      it "creates a long position" do
        paper_broker.buy(symbol, quantity, price)

        positions = paper_broker.instance_variable_get(:@positions)
        expect(positions.length).to eq(1)
        expect(positions.first[:symbol]).to eq(symbol)
        expect(positions.first[:quantity]).to eq(quantity)
        expect(positions.first[:side]).to eq("LONG")
        expect(positions.first[:avg_price]).to eq(price)
      end
    end

    context "when insufficient balance is available" do
      before do
        allow(mock_balance_provider).to receive(:available_balance).and_return(1000.0)
      end

      it "returns failure status" do
        result = paper_broker.buy(symbol, quantity, price)

        expect(result[:status]).to eq("FAILED")
        expect(result[:error]).to include("Insufficient balance")
      end

      it "does not add order to orders list" do
        paper_broker.buy(symbol, quantity, price)

        orders = paper_broker.instance_variable_get(:@orders)
        expect(orders.length).to eq(0)
      end

      it "does not update balance provider" do
        paper_broker.buy(symbol, quantity, price)

        expect(mock_balance_provider).not_to have_received(:update_balance)
      end

      it "does not create position" do
        paper_broker.buy(symbol, quantity, price)

        positions = paper_broker.instance_variable_get(:@positions)
        expect(positions.length).to eq(0)
      end
    end

    context "edge cases" do
      it "handles zero quantity" do
        result = paper_broker.buy(symbol, 0, price)
        expect(result[:status]).to eq("FAILED")
        expect(result[:error]).to include("Invalid quantity")
      end

      it "handles negative quantity" do
        result = paper_broker.buy(symbol, -100, price)
        expect(result[:status]).to eq("FAILED")
        expect(result[:error]).to include("Invalid quantity")
      end

      it "handles zero price" do
        result = paper_broker.buy(symbol, quantity, 0)
        expect(result[:status]).to eq("FAILED")
        expect(result[:error]).to include("Invalid price")
      end

      it "handles negative price" do
        result = paper_broker.buy(symbol, quantity, -50.0)
        expect(result[:status]).to eq("FAILED")
        expect(result[:error]).to include("Invalid price")
      end

      it "handles very large quantities" do
        large_quantity = 1_000_000
        result = paper_broker.buy(symbol, large_quantity, price)
        expect(result[:status]).to eq("FAILED")
        expect(result[:error]).to include("Insufficient balance")
      end

      it "handles very high prices" do
        high_price = 1_000_000.0
        result = paper_broker.buy(symbol, quantity, high_price)
        expect(result[:status]).to eq("FAILED")
        expect(result[:error]).to include("Insufficient balance")
      end
    end
  end

  describe "#sell" do
    let(:symbol) { "NIFTY" }
    let(:quantity) { 100 }
    let(:price) { 50.0 }

    context "when no existing position" do
      it "returns failure status for short selling without position" do
        result = paper_broker.sell(symbol, quantity, price)

        expect(result[:status]).to eq("FAILED")
        expect(result[:error]).to include("No position to sell")
      end
    end

    context "when existing long position exists" do
      before do
        # First create a long position
        allow(mock_balance_provider).to receive(:available_balance).and_return(100_000.0)
        paper_broker.buy(symbol, quantity, 45.0)
      end

      it "sells existing position successfully" do
        result = paper_broker.sell(symbol, quantity, price)

        expect(result[:status]).to eq("SUCCESS")
        expect(result[:action]).to eq("SELL")
        expect(result[:symbol]).to eq(symbol)
        expect(result[:quantity]).to eq(quantity)
        expect(result[:price]).to eq(price)
      end

      it "adds sell order to orders list" do
        paper_broker.sell(symbol, quantity, price)

        orders = paper_broker.instance_variable_get(:@orders)
        expect(orders.length).to eq(2) # Buy + Sell
        expect(orders.last[:action]).to eq("SELL")
      end

      it "updates balance provider with credit" do
        paper_broker.sell(symbol, quantity, price)

        total_proceeds = quantity * price
        expect(mock_balance_provider).to have_received(:update_balance).with(total_proceeds, type: :credit)
      end

      it "removes the position after selling" do
        paper_broker.sell(symbol, quantity, price)

        positions = paper_broker.instance_variable_get(:@positions)
        expect(positions.length).to eq(0)
      end
    end

    context "when partial position exists" do
      before do
        # Create a position with 200 quantity
        allow(mock_balance_provider).to receive(:available_balance).and_return(100_000.0)
        paper_broker.buy(symbol, 200, 45.0)
      end

      it "allows partial selling" do
        result = paper_broker.sell(symbol, 100, price)

        expect(result[:status]).to eq("SUCCESS")
        expect(result[:quantity]).to eq(100)
      end

      it "updates position quantity after partial sell" do
        paper_broker.sell(symbol, 100, price)

        positions = paper_broker.instance_variable_get(:@positions)
        expect(positions.length).to eq(1)
        expect(positions.first[:quantity]).to eq(100)
      end
    end
  end

  describe "#square_off" do
    let(:symbol) { "NIFTY" }
    let(:quantity) { 100 }

    context "when no position exists" do
      it "returns failure status" do
        result = paper_broker.square_off(symbol, quantity)

        expect(result[:status]).to eq("FAILED")
        expect(result[:error]).to include("No position to square off")
      end
    end

    context "when position exists" do
      before do
        # Create a long position
        allow(mock_balance_provider).to receive(:available_balance).and_return(100_000.0)
        paper_broker.buy(symbol, quantity, 45.0)
      end

      it "squares off position successfully" do
        result = paper_broker.square_off(symbol, quantity)

        expect(result[:status]).to eq("SUCCESS")
        expect(result[:action]).to eq("SQUARE_OFF")
        expect(result[:symbol]).to eq(symbol)
        expect(result[:quantity]).to eq(quantity)
      end

      it "removes the position" do
        paper_broker.square_off(symbol, quantity)

        positions = paper_broker.instance_variable_get(:@positions)
        expect(positions.length).to eq(0)
      end

      it "adds square off order to orders list" do
        paper_broker.square_off(symbol, quantity)

        orders = paper_broker.instance_variable_get(:@orders)
        expect(orders.length).to eq(2) # Buy + Square Off
        expect(orders.last[:action]).to eq("SQUARE_OFF")
      end
    end
  end

  describe "#get_positions" do
    it "returns empty array when no positions" do
      positions = paper_broker.get_positions
      expect(positions).to eq([])
    end

    it "returns all current positions" do
      # Create multiple positions
      allow(mock_balance_provider).to receive(:available_balance).and_return(100_000.0)
      paper_broker.buy("NIFTY", 100, 50.0)
      paper_broker.buy("BANKNIFTY", 50, 100.0)

      positions = paper_broker.get_positions
      expect(positions.length).to eq(2)
      expect(positions.map { |p| p[:symbol] }).to contain_exactly("NIFTY", "BANKNIFTY")
    end
  end

  describe "#get_orders" do
    it "returns empty array when no orders" do
      orders = paper_broker.get_orders
      expect(orders).to eq([])
    end

    it "returns all orders in chronological order" do
      # Create multiple orders
      allow(mock_balance_provider).to receive(:available_balance).and_return(100_000.0)
      paper_broker.buy("NIFTY", 100, 50.0)
      paper_broker.sell("NIFTY", 100, 55.0)
      paper_broker.buy("BANKNIFTY", 50, 100.0)

      orders = paper_broker.get_orders
      expect(orders.length).to eq(3)
      expect(orders[0][:action]).to eq("BUY")
      expect(orders[1][:action]).to eq("SELL")
      expect(orders[2][:action]).to eq("BUY")
    end
  end

  describe "order ID generation" do
    it "generates unique order IDs" do
      allow(mock_balance_provider).to receive(:available_balance).and_return(100_000.0)

      order1 = paper_broker.buy("NIFTY", 100, 50.0)
      order2 = paper_broker.buy("BANKNIFTY", 50, 100.0)

      expect(order1[:order_id]).not_to eq(order2[:order_id])
      expect(order1[:order_id]).to match(/PAPER_ORDER_\d+/)
      expect(order2[:order_id]).to match(/PAPER_ORDER_\d+/)
    end
  end

  describe "balance integration" do
    it "tracks balance changes correctly" do
      initial_balance = 100_000.0
      allow(mock_balance_provider).to receive(:available_balance).and_return(initial_balance)

      # Buy order
      paper_broker.buy("NIFTY", 100, 50.0)
      expect(mock_balance_provider).to have_received(:update_balance).with(5000.0, type: :debit)

      # Sell order
      paper_broker.sell("NIFTY", 100, 55.0)
      expect(mock_balance_provider).to have_received(:update_balance).with(5500.0, type: :credit)
    end
  end
end
