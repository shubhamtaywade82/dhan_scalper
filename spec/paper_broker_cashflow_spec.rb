# frozen_string_literal: true

require "spec_helper"

RSpec.describe DhanScalper::Brokers::PaperBroker do
  let(:virtual_data_manager) { double("VirtualDataManager") }
  let(:balance_provider) { DhanScalper::BalanceProviders::PaperWallet.new(starting_balance: 100_000) }
  let(:broker) { described_class.new(virtual_data_manager: virtual_data_manager, balance_provider: balance_provider) }
  let(:security_id) { "TEST123" }
  let(:segment) { "NSE_EQ" }

  before do
    # Mock the virtual data manager
    allow(virtual_data_manager).to receive(:get_positions).and_return([])
    allow(virtual_data_manager).to receive(:remove_position)
    allow(virtual_data_manager).to receive(:add_order)
    allow(virtual_data_manager).to receive(:add_position)

    # Mock the tick cache
    allow(DhanScalper::TickCache).to receive(:ltp).and_return(100.0)
  end

  describe "Buy->Sell profit scenario" do
    it "correctly handles buy 75@100, sell 75@120 with fees" do
      # Initial balance: 100,000
      expect(balance_provider.available_balance).to eq(DhanScalper::Support::Money.bd(100_000))
      expect(balance_provider.realized_pnl).to eq(DhanScalper::Support::Money.bd(0))

      # Mock position tracking
      positions = []
      allow(virtual_data_manager).to receive(:get_positions).and_return(positions)
      allow(virtual_data_manager).to receive(:remove_position) do |id|
        positions.reject! { |pos| pos[:security_id] == id }
      end

      # Buy 75 units @ 100
      allow(DhanScalper::TickCache).to receive(:ltp).with(segment, security_id).and_return(100.0)

      buy_order = broker.buy_market(segment: segment, security_id: security_id, quantity: 75)

      # Expected: balance -= (100 * 75) + 20 = 7520
      # New balance: 100,000 - 7,520 = 92,480
      expect(balance_provider.available_balance).to eq(DhanScalper::Support::Money.bd(92_480))
      expect(balance_provider.realized_pnl).to eq(DhanScalper::Support::Money.bd(0))

      # Add position to mock
      positions << {
        security_id: security_id,
        quantity: 75,
        entry_price: 100.0
      }

      # Sell 75 units @ 120
      allow(DhanScalper::TickCache).to receive(:ltp).with(segment, security_id).and_return(120.0)

      sell_order = broker.sell_market(segment: segment, security_id: security_id, quantity: 75)

      # Expected calculations:
      # Gross proceeds: 120 * 75 = 9,000
      # Net proceeds: 9,000 - 20 = 8,980
      # Final balance: 92,480 + 8,980 = 101,460
      # Realized PnL: (120 - 100) * 75 = 1,500
      expect(balance_provider.available_balance).to eq(DhanScalper::Support::Money.bd(101_460))
      expect(balance_provider.realized_pnl).to eq(DhanScalper::Support::Money.bd(1_500))
    end
  end

  describe "Buy->Sell loss scenario" do
    it "correctly handles buy 75@100, sell 75@90 with fees" do
      # Initial balance: 100,000
      expect(balance_provider.available_balance).to eq(DhanScalper::Support::Money.bd(100_000))
      expect(balance_provider.realized_pnl).to eq(DhanScalper::Support::Money.bd(0))

      # Mock position tracking
      positions = []
      allow(virtual_data_manager).to receive(:get_positions).and_return(positions)
      allow(virtual_data_manager).to receive(:remove_position) do |id|
        positions.reject! { |pos| pos[:security_id] == id }
      end

      # Buy 75 units @ 100
      allow(DhanScalper::TickCache).to receive(:ltp).with(segment, security_id).and_return(100.0)

      buy_order = broker.buy_market(segment: segment, security_id: security_id, quantity: 75)

      # Expected: balance -= (100 * 75) + 20 = 7520
      # New balance: 100,000 - 7,520 = 92,480
      expect(balance_provider.available_balance).to eq(DhanScalper::Support::Money.bd(92_480))
      expect(balance_provider.realized_pnl).to eq(DhanScalper::Support::Money.bd(0))

      # Add position to mock
      positions << {
        security_id: security_id,
        quantity: 75,
        entry_price: 100.0
      }

      # Sell 75 units @ 90
      allow(DhanScalper::TickCache).to receive(:ltp).with(segment, security_id).and_return(90.0)

      sell_order = broker.sell_market(segment: segment, security_id: security_id, quantity: 75)

      # Expected calculations:
      # Gross proceeds: 90 * 75 = 6,750
      # Net proceeds: 6,750 - 20 = 6,730
      # Final balance: 92,480 + 6,730 = 99,210
      # Realized PnL: (90 - 100) * 75 = -750
      expect(balance_provider.available_balance).to eq(DhanScalper::Support::Money.bd(99_210))
      expect(balance_provider.realized_pnl).to eq(DhanScalper::Support::Money.bd(-750))
    end
  end

  describe "Fees applied on both orders" do
    it "tracks total fees of 40 per round trip" do
      # Mock position tracking
      positions = []
      allow(virtual_data_manager).to receive(:get_positions).and_return(positions)
      allow(virtual_data_manager).to receive(:remove_position) do |id|
        positions.reject! { |pos| pos[:security_id] == id }
      end

      # Buy 75 units @ 100
      allow(DhanScalper::TickCache).to receive(:ltp).with(segment, security_id).and_return(100.0)
      broker.buy_market(segment: segment, security_id: security_id, quantity: 75)

      # Add position to mock
      positions << {
        security_id: security_id,
        quantity: 75,
        entry_price: 100.0
      }

      # Sell 75 units @ 120
      allow(DhanScalper::TickCache).to receive(:ltp).with(segment, security_id).and_return(120.0)
      broker.sell_market(segment: segment, security_id: security_id, quantity: 75)

      # Verify total fees: 20 (buy) + 20 (sell) = 40
      # Starting balance: 100,000
      # Buy cost: 7,520 (7,500 + 20 fee)
      # Sell proceeds: 8,980 (9,000 - 20 fee)
      # Final balance: 100,000 - 7,520 + 8,980 = 101,460
      # Total fees: 100,000 - 101,460 + 1,500 (PnL) = 40
      expect(balance_provider.available_balance).to eq(DhanScalper::Support::Money.bd(101_460))
      expect(balance_provider.realized_pnl).to eq(DhanScalper::Support::Money.bd(1_500))
    end
  end

  describe "place_order method" do
    it "handles BUY orders with correct cash flow" do
      # Mock position tracking
      positions = []
      allow(virtual_data_manager).to receive(:get_positions).and_return(positions)
      allow(virtual_data_manager).to receive(:remove_position) do |id|
        positions.reject! { |pos| pos[:security_id] == id }
      end

      # Buy 75 units @ 100
      result = broker.place_order(
        symbol: "TEST",
        instrument_id: security_id,
        side: "BUY",
        quantity: 75,
        price: 100.0
      )

      expect(result[:success]).to be true
      expect(balance_provider.available_balance).to eq(DhanScalper::Support::Money.bd(92_480))
    end

    it "handles SELL orders with correct cash flow" do
      # Mock position tracking
      positions = []
      allow(virtual_data_manager).to receive(:get_positions).and_return(positions)
      allow(virtual_data_manager).to receive(:remove_position) do |id|
        positions.reject! { |pos| pos[:security_id] == id }
      end

      # Add a position first
      positions << {
        security_id: security_id,
        quantity: 75,
        entry_price: 100.0
      }

      # Sell 75 units @ 120
      result = broker.place_order(
        symbol: "TEST",
        instrument_id: security_id,
        side: "SELL",
        quantity: 75,
        price: 120.0
      )

      expect(result[:success]).to be true
      expect(balance_provider.available_balance).to eq(DhanScalper::Support::Money.bd(108_980)) # 100,000 + 8,980
      expect(balance_provider.realized_pnl).to eq(DhanScalper::Support::Money.bd(1_500))
    end
  end
end
