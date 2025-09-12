# frozen_string_literal: true

require "spec_helper"

RSpec.describe DhanScalper::VirtualDataManager do
  let(:virtual_data_manager) { described_class.new }

  describe "#initialize" do
    it "initializes with default values" do
      expect(virtual_data_manager.instance_variable_get(:@balance)).to eq(100_000.0)
      expect(virtual_data_manager.instance_variable_get(:@orders)).to eq([])
      expect(virtual_data_manager.instance_variable_get(:@positions)).to eq([])
      expect(virtual_data_manager.instance_variable_get(:@order_id_counter)).to eq(1)
    end

    it "allows custom starting balance" do
      custom_manager = described_class.new(starting_balance: 500_000.0)
      expect(custom_manager.instance_variable_get(:@balance)).to eq(500_000.0)
    end
  end

  describe "#get_balance" do
    it "returns current balance" do
      expect(virtual_data_manager.get_balance).to eq(100_000.0)
    end

    it "returns updated balance after transactions" do
      virtual_data_manager.place_order("NIFTY", "BUY", 100, 50.0)
      expect(virtual_data_manager.get_balance).to eq(95_000.0)
    end
  end

  describe "#place_order" do
    let(:symbol) { "NIFTY" }
    let(:action) { "BUY" }
    let(:quantity) { 100 }
    let(:price) { 50.0 }

    context "when sufficient balance is available" do
      it "places buy order successfully" do
        result = virtual_data_manager.place_order(symbol, action, quantity, price)

        expect(result[:status]).to eq("SUCCESS")
        expect(result[:order_id]).to eq("VIRTUAL_ORDER_1")
        expect(result[:symbol]).to eq(symbol)
        expect(result[:action]).to eq(action)
        expect(result[:quantity]).to eq(quantity)
        expect(result[:price]).to eq(price)
      end

      it "deducts cost from balance" do
        initial_balance = virtual_data_manager.get_balance
        virtual_data_manager.place_order(symbol, action, quantity, price)

        expected_balance = initial_balance - (quantity * price)
        expect(virtual_data_manager.get_balance).to eq(expected_balance)
      end

      it "adds order to orders list" do
        virtual_data_manager.place_order(symbol, action, quantity, price)

        orders = virtual_data_manager.instance_variable_get(:@orders)
        expect(orders.length).to eq(1)
        expect(orders.first[:symbol]).to eq(symbol)
        expect(orders.first[:action]).to eq(action)
      end

      it "creates position for buy orders" do
        virtual_data_manager.place_order(symbol, action, quantity, price)

        positions = virtual_data_manager.instance_variable_get(:@positions)
        expect(positions.length).to eq(1)
        expect(positions.first[:symbol]).to eq(symbol)
        expect(positions.first[:quantity]).to eq(quantity)
        expect(positions.first[:side]).to eq("LONG")
        expect(positions.first[:avg_price]).to eq(price)
      end
    end

    context "when insufficient balance is available" do
      let(:large_quantity) { 10_000 }
      let(:high_price) { 100.0 }

      it "returns failure status" do
        result = virtual_data_manager.place_order(symbol, action, large_quantity, high_price)

        expect(result[:status]).to eq("FAILED")
        expect(result[:error]).to include("Insufficient balance")
      end

      it "does not deduct from balance" do
        initial_balance = virtual_data_manager.get_balance
        virtual_data_manager.place_order(symbol, action, large_quantity, high_price)

        expect(virtual_data_manager.get_balance).to eq(initial_balance)
      end

      it "does not add order to orders list" do
        virtual_data_manager.place_order(symbol, action, large_quantity, high_price)

        orders = virtual_data_manager.instance_variable_get(:@orders)
        expect(orders.length).to eq(0)
      end

      it "does not create position" do
        virtual_data_manager.place_order(symbol, action, large_quantity, high_price)

        positions = virtual_data_manager.instance_variable_get(:@positions)
        expect(positions.length).to eq(0)
      end
    end

    context "with sell orders" do
      before do
        # First create a long position
        virtual_data_manager.place_order(symbol, "BUY", quantity, 45.0)
      end

      it "sells existing position successfully" do
        result = virtual_data_manager.place_order(symbol, "SELL", quantity, price)

        expect(result[:status]).to eq("SUCCESS")
        expect(result[:action]).to eq("SELL")
        expect(result[:price]).to eq(price)
      end

      it "adds proceeds to balance" do
        initial_balance = virtual_data_manager.get_balance
        virtual_data_manager.place_order(symbol, "SELL", quantity, price)

        expected_balance = initial_balance + (quantity * price)
        expect(virtual_data_manager.get_balance).to eq(expected_balance)
      end

      it "removes position after selling" do
        virtual_data_manager.place_order(symbol, "SELL", quantity, price)

        positions = virtual_data_manager.instance_variable_get(:@positions)
        expect(positions.length).to eq(0)
      end
    end

    context "edge cases" do
      it "handles zero quantity" do
        result = virtual_data_manager.place_order(symbol, action, 0, price)
        expect(result[:status]).to eq("FAILED")
        expect(result[:error]).to include("Invalid quantity")
      end

      it "handles negative quantity" do
        result = virtual_data_manager.place_order(symbol, action, -100, price)
        expect(result[:status]).to eq("FAILED")
        expect(result[:error]).to include("Invalid quantity")
      end

      it "handles zero price" do
        result = virtual_data_manager.place_order(symbol, action, quantity, 0)
        expect(result[:status]).to eq("FAILED")
        expect(result[:error]).to include("Invalid price")
      end

      it "handles negative price" do
        result = virtual_data_manager.place_order(symbol, action, quantity, -50.0)
        expect(result[:status]).to eq("FAILED")
        expect(result[:error]).to include("Invalid price")
      end

      it "handles invalid action" do
        result = virtual_data_manager.place_order(symbol, "INVALID", quantity, price)
        expect(result[:status]).to eq("FAILED")
        expect(result[:error]).to include("Invalid action")
      end
    end
  end

  describe "#get_orders" do
    it "returns empty array when no orders" do
      orders = virtual_data_manager.get_orders
      expect(orders).to eq([])
    end

    it "returns all orders in chronological order" do
      virtual_data_manager.place_order("NIFTY", "BUY", 100, 50.0)
      virtual_data_manager.place_order("BANKNIFTY", "BUY", 50, 100.0)

      orders = virtual_data_manager.get_orders
      expect(orders.length).to eq(2)
      expect(orders[0][:symbol]).to eq("NIFTY")
      expect(orders[1][:symbol]).to eq("BANKNIFTY")
    end
  end

  describe "#get_positions" do
    it "returns empty array when no positions" do
      positions = virtual_data_manager.get_positions
      expect(positions).to eq([])
    end

    it "returns all current positions" do
      virtual_data_manager.place_order("NIFTY", "BUY", 100, 50.0)
      virtual_data_manager.place_order("BANKNIFTY", "BUY", 50, 100.0)

      positions = virtual_data_manager.get_positions
      expect(positions.length).to eq(2)
      expect(positions.map { |p| p[:symbol] }).to contain_exactly("NIFTY", "BANKNIFTY")
    end

    it "updates position quantities after partial sells" do
      virtual_data_manager.place_order("NIFTY", "BUY", 200, 50.0)
      virtual_data_manager.place_order("NIFTY", "SELL", 100, 55.0)

      positions = virtual_data_manager.get_positions
      expect(positions.length).to eq(1)
      expect(positions.first[:quantity]).to eq(100)
    end
  end

  describe "#get_pnl" do
    it "returns zero PnL when no positions" do
      pnl = virtual_data_manager.get_pnl
      expect(pnl).to eq(0.0)
    end

    it "calculates PnL for long positions" do
      # Buy at 50, current price 55
      virtual_data_manager.place_order("NIFTY", "BUY", 100, 50.0)

      pnl = virtual_data_manager.get_pnl("NIFTY", 55.0)
      expected_pnl = (55.0 - 50.0) * 100
      expect(pnl).to eq(expected_pnl)
    end

    it "calculates PnL for multiple positions" do
      virtual_data_manager.place_order("NIFTY", "BUY", 100, 50.0)
      virtual_data_manager.place_order("BANKNIFTY", "BUY", 50, 100.0)

      total_pnl = virtual_data_manager.get_pnl("NIFTY", 55.0) + virtual_data_manager.get_pnl("BANKNIFTY", 105.0)
      expect(total_pnl).to be > 0
    end

    it "handles negative PnL" do
      virtual_data_manager.place_order("NIFTY", "BUY", 100, 50.0)

      pnl = virtual_data_manager.get_pnl("NIFTY", 45.0)
      expected_pnl = (45.0 - 50.0) * 100
      expect(pnl).to eq(expected_pnl)
      expect(pnl).to be < 0
    end
  end

  describe "order ID generation" do
    it "generates sequential order IDs" do
      order1 = virtual_data_manager.place_order("NIFTY", "BUY", 100, 50.0)
      order2 = virtual_data_manager.place_order("BANKNIFTY", "BUY", 50, 100.0)

      expect(order1[:order_id]).to eq("VIRTUAL_ORDER_1")
      expect(order2[:order_id]).to eq("VIRTUAL_ORDER_2")
    end

    it "increments counter for each order" do
      expect(virtual_data_manager.instance_variable_get(:@order_id_counter)).to eq(1)

      virtual_data_manager.place_order("NIFTY", "BUY", 100, 50.0)
      expect(virtual_data_manager.instance_variable_get(:@order_id_counter)).to eq(2)

      virtual_data_manager.place_order("BANKNIFTY", "BUY", 50, 100.0)
      expect(virtual_data_manager.instance_variable_get(:@order_id_counter)).to eq(3)
    end
  end

  describe "position management" do
    it "aggregates multiple buy orders for same symbol" do
      virtual_data_manager.place_order("NIFTY", "BUY", 100, 50.0)
      virtual_data_manager.place_order("NIFTY", "BUY", 100, 55.0)

      positions = virtual_data_manager.get_positions
      expect(positions.length).to eq(1)
      expect(positions.first[:quantity]).to eq(200)
      expect(positions.first[:avg_price]).to eq(52.5) # (50*100 + 55*100) / 200
    end

    it "handles partial position closure" do
      virtual_data_manager.place_order("NIFTY", "BUY", 200, 50.0)
      virtual_data_manager.place_order("NIFTY", "SELL", 100, 55.0)

      positions = virtual_data_manager.get_positions
      expect(positions.length).to eq(1)
      expect(positions.first[:quantity]).to eq(100)
      expect(positions.first[:avg_price]).to eq(50.0) # Remaining position keeps original price
    end

    it "removes position when fully closed" do
      virtual_data_manager.place_order("NIFTY", "BUY", 100, 50.0)
      virtual_data_manager.place_order("NIFTY", "SELL", 100, 55.0)

      positions = virtual_data_manager.get_positions
      expect(positions.length).to eq(0)
    end
  end

  describe "balance validation" do
    it "prevents balance from going negative" do
      # Try to place order larger than balance
      result = virtual_data_manager.place_order("NIFTY", "BUY", 10_000, 100.0)

      expect(result[:status]).to eq("FAILED")
      expect(virtual_data_manager.get_balance).to eq(100_000.0)
    end

    it "allows balance to reach zero" do
      # Place order exactly equal to balance
      result = virtual_data_manager.place_order("NIFTY", "BUY", 1_000, 100.0)

      expect(result[:status]).to eq("SUCCESS")
      expect(virtual_data_manager.get_balance).to eq(0.0)
    end
  end

  describe "data consistency" do
    it "maintains consistency between orders and positions" do
      virtual_data_manager.place_order("NIFTY", "BUY", 100, 50.0)
      virtual_data_manager.place_order("NIFTY", "SELL", 100, 55.0)

      orders = virtual_data_manager.get_orders
      positions = virtual_data_manager.get_positions

      expect(orders.length).to eq(2)
      expect(positions.length).to eq(0)
    end

    it "tracks all transactions accurately" do
      initial_balance = virtual_data_manager.get_balance

      # Buy order
      virtual_data_manager.place_order("NIFTY", "BUY", 100, 50.0)
      buy_balance = virtual_data_manager.get_balance

      # Sell order
      virtual_data_manager.place_order("NIFTY", "SELL", 100, 55.0)
      final_balance = virtual_data_manager.get_balance

      # Verify balance changes
      expect(buy_balance).to eq(initial_balance - 5_000.0)
      expect(final_balance).to eq(buy_balance + 5_500.0)
      expect(final_balance).to eq(initial_balance + 500.0) # Net profit
    end
  end
end
