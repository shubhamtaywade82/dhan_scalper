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
    allow(virtual_data_manager).to receive(:add_order)
    allow(virtual_data_manager).to receive(:add_position)

    # Mock the tick cache
    allow(DhanScalper::TickCache).to receive(:ltp).and_return(100.0)
  end

  describe "Average up scenario" do
    it "correctly handles multiple entries with weighted averaging" do
      # Initial balance: 100,000
      expect(balance_provider.available_balance).to eq(DhanScalper::Support::Money.bd(100_000))

      # First entry: 75 @ 100
      allow(DhanScalper::TickCache).to receive(:ltp).with(segment, security_id).and_return(100.0)
      buy_order1 = broker.buy_market(segment: segment, security_id: security_id, quantity: 75)

      # Expected: balance -= (100 * 75) + 20 = 7,520
      # New balance: 100,000 - 7,520 = 92,480
      expect(balance_provider.available_balance).to eq(DhanScalper::Support::Money.bd(92_480))

      # Check position after first entry
      position = broker.position_tracker.get_position(exchange_segment: segment, security_id: security_id, side: "LONG")
      expect(position[:buy_qty]).to eq(DhanScalper::Support::Money.bd(75))
      expect(position[:buy_avg]).to eq(DhanScalper::Support::Money.bd(100))
      expect(position[:net_qty]).to eq(DhanScalper::Support::Money.bd(75))

      # Second entry: 75 @ 120 (averaging up)
      allow(DhanScalper::TickCache).to receive(:ltp).with(segment, security_id).and_return(120.0)
      buy_order2 = broker.buy_market(segment: segment, security_id: security_id, quantity: 75)

      # Expected: balance -= (120 * 75) + 20 = 9,020
      # New balance: 92,480 - 9,020 = 83,460
      expect(balance_provider.available_balance).to eq(DhanScalper::Support::Money.bd(83_460))

      # Check position after second entry (weighted average)
      position = broker.position_tracker.get_position(exchange_segment: segment, security_id: security_id, side: "LONG")
      expect(position[:buy_qty]).to eq(DhanScalper::Support::Money.bd(150)) # 75 + 75
      expect(position[:buy_avg]).to eq(DhanScalper::Support::Money.bd(110)) # (100*75 + 120*75) / 150 = 110
      expect(position[:net_qty]).to eq(DhanScalper::Support::Money.bd(150))

      # Partial exit: 75 @ 130
      allow(DhanScalper::TickCache).to receive(:ltp).with(segment, security_id).and_return(130.0)
      sell_order = broker.sell_market(segment: segment, security_id: security_id, quantity: 75)

      # Expected calculations:
      # Gross proceeds: 130 * 75 = 9,750
      # Net proceeds: 9,750 - 20 = 9,730
      # Final balance: 83,460 + 9,730 = 93,190
      # Realized PnL: (130 - 110) * 75 = 1,500
      expect(balance_provider.available_balance).to eq(DhanScalper::Support::Money.bd(93_190))
      expect(balance_provider.realized_pnl).to eq(DhanScalper::Support::Money.bd(1_500))

      # Check position after partial exit
      position = broker.position_tracker.get_position(exchange_segment: segment, security_id: security_id, side: "LONG")
      expect(position[:net_qty]).to eq(DhanScalper::Support::Money.bd(75)) # 150 - 75
      expect(position[:buy_avg]).to eq(DhanScalper::Support::Money.bd(110)) # Should remain unchanged
      expect(position[:sell_qty]).to eq(DhanScalper::Support::Money.bd(75))
      expect(position[:sell_avg]).to eq(DhanScalper::Support::Money.bd(130))
    end
  end

  describe "Half exit profit then final exit loss scenario" do
    it "correctly handles cumulative realized PnL and fees" do
      # Initial balance: 100,000
      expect(balance_provider.available_balance).to eq(DhanScalper::Support::Money.bd(100_000))

      # Entry: 100 @ 100
      allow(DhanScalper::TickCache).to receive(:ltp).with(segment, security_id).and_return(100.0)
      buy_order = broker.buy_market(segment: segment, security_id: security_id, quantity: 100)

      # Expected: balance -= (100 * 100) + 20 = 10,020
      # New balance: 100,000 - 10,020 = 89,980
      expect(balance_provider.available_balance).to eq(DhanScalper::Support::Money.bd(89_980))

      # Half exit profit: 50 @ 120
      allow(DhanScalper::TickCache).to receive(:ltp).with(segment, security_id).and_return(120.0)
      sell_order1 = broker.sell_market(segment: segment, security_id: security_id, quantity: 50)

      # Expected calculations:
      # Gross proceeds: 120 * 50 = 6,000
      # Net proceeds: 6,000 - 20 = 5,980
      # Balance: 89,980 + 5,980 = 95,960
      # Realized PnL: (120 - 100) * 50 = 1,000
      expect(balance_provider.available_balance).to eq(DhanScalper::Support::Money.bd(95_960))
      expect(balance_provider.realized_pnl).to eq(DhanScalper::Support::Money.bd(1_000))

      # Check position after half exit
      position = broker.position_tracker.get_position(exchange_segment: segment, security_id: security_id, side: "LONG")
      expect(position[:net_qty]).to eq(DhanScalper::Support::Money.bd(50)) # 100 - 50
      expect(position[:buy_avg]).to eq(DhanScalper::Support::Money.bd(100)) # Should remain unchanged

      # Final exit loss: 50 @ 90
      allow(DhanScalper::TickCache).to receive(:ltp).with(segment, security_id).and_return(90.0)
      sell_order2 = broker.sell_market(segment: segment, security_id: security_id, quantity: 50)

      # Expected calculations:
      # Gross proceeds: 90 * 50 = 4,500
      # Net proceeds: 4,500 - 20 = 4,480
      # Final balance: 95,960 + 4,480 = 100,440
      # Additional realized PnL: (90 - 100) * 50 = -500
      # Total realized PnL: 1,000 + (-500) = 500
      expect(balance_provider.available_balance).to eq(DhanScalper::Support::Money.bd(100_440))
      expect(balance_provider.realized_pnl).to eq(DhanScalper::Support::Money.bd(500))

      # Check position after final exit
      position = broker.position_tracker.get_position(exchange_segment: segment, security_id: security_id, side: "LONG")
      expect(position[:net_qty]).to eq(DhanScalper::Support::Money.bd(0)) # 50 - 50
      expect(position[:sell_qty]).to eq(DhanScalper::Support::Money.bd(100)) # 50 + 50

      # Verify total fees: 20 (buy) + 20 (sell1) + 20 (sell2) = 60
      # Starting balance: 100,000
      # Final balance: 100,440
      # Realized PnL: 500
      # Net effect: 100,440 - 100,000 = 440 (which is 500 PnL - 60 fees)
    end
  end

  describe "Multiple entries with different quantities" do
    it "correctly calculates weighted average for different entry sizes" do
      # Entry 1: 100 @ 100
      allow(DhanScalper::TickCache).to receive(:ltp).with(segment, security_id).and_return(100.0)
      broker.buy_market(segment: segment, security_id: security_id, quantity: 100)

      # Entry 2: 50 @ 120
      allow(DhanScalper::TickCache).to receive(:ltp).with(segment, security_id).and_return(120.0)
      broker.buy_market(segment: segment, security_id: security_id, quantity: 50)

      # Check weighted average calculation
      position = broker.position_tracker.get_position(exchange_segment: segment, security_id: security_id, side: "LONG")
      expect(position[:buy_qty]).to eq(DhanScalper::Support::Money.bd(150)) # 100 + 50
      # Weighted average: (100*100 + 120*50) / 150 = (10,000 + 6,000) / 150 = 106.67
      # Check that the average is approximately 106.67
      expect(position[:buy_avg]).to be > DhanScalper::Support::Money.bd(106.6)
      expect(position[:buy_avg]).to be < DhanScalper::Support::Money.bd(106.7)
      expect(position[:net_qty]).to eq(DhanScalper::Support::Money.bd(150))
    end
  end

  describe "Partial exit with insufficient quantity" do
    it "only sells available quantity when trying to sell more than held" do
      # Entry: 50 @ 100
      allow(DhanScalper::TickCache).to receive(:ltp).with(segment, security_id).and_return(100.0)
      broker.buy_market(segment: segment, security_id: security_id, quantity: 50)

      # Try to sell 75 (more than held)
      allow(DhanScalper::TickCache).to receive(:ltp).with(segment, security_id).and_return(120.0)
      sell_order = broker.sell_market(segment: segment, security_id: security_id, quantity: 75)

      # Should only sell 50 (what's available)
      position = broker.position_tracker.get_position(exchange_segment: segment, security_id: security_id, side: "LONG")
      expect(position[:net_qty]).to eq(DhanScalper::Support::Money.bd(0)) # All sold
      expect(position[:sell_qty]).to eq(DhanScalper::Support::Money.bd(50)) # Only 50 sold
    end
  end

  describe "Unrealized PnL tracking" do
    it "correctly calculates unrealized PnL on remaining positions" do
      # Entry: 100 @ 100
      allow(DhanScalper::TickCache).to receive(:ltp).with(segment, security_id).and_return(100.0)
      broker.buy_market(segment: segment, security_id: security_id, quantity: 100)

      # Partial exit: 50 @ 120
      allow(DhanScalper::TickCache).to receive(:ltp).with(segment, security_id).and_return(120.0)
      broker.sell_market(segment: segment, security_id: security_id, quantity: 50)

      # Update unrealized PnL with current LTP
      ltp_provider = ->(seg, sec_id) { 130.0 }
      unrealized_pnl = broker.position_tracker.update_unrealized_pnl(ltp_provider)

      # Expected unrealized PnL: (130 - 100) * 50 = 1,500
      expect(unrealized_pnl).to eq(DhanScalper::Support::Money.bd(1_500))

      # Check position unrealized PnL
      position = broker.position_tracker.get_position(exchange_segment: segment, security_id: security_id, side: "LONG")
      expect(position[:unrealized_pnl]).to eq(DhanScalper::Support::Money.bd(1_500))
      expect(position[:current_price]).to eq(DhanScalper::Support::Money.bd(130))
    end
  end

  describe "Day quantities tracking" do
    it "correctly tracks day buy and sell quantities" do
      # Entry: 100 @ 100
      allow(DhanScalper::TickCache).to receive(:ltp).with(segment, security_id).and_return(100.0)
      broker.buy_market(segment: segment, security_id: security_id, quantity: 100)

      # Partial exit: 30 @ 120
      allow(DhanScalper::TickCache).to receive(:ltp).with(segment, security_id).and_return(120.0)
      broker.sell_market(segment: segment, security_id: security_id, quantity: 30)

      position = broker.position_tracker.get_position(exchange_segment: segment, security_id: security_id, side: "LONG")
      expect(position[:day_buy_qty]).to eq(DhanScalper::Support::Money.bd(100))
      expect(position[:day_sell_qty]).to eq(DhanScalper::Support::Money.bd(30))

      # Reset day quantities
      broker.position_tracker.reset_day_quantities
      position = broker.position_tracker.get_position(exchange_segment: segment, security_id: security_id, side: "LONG")
      expect(position[:day_buy_qty]).to eq(DhanScalper::Support::Money.bd(0))
      expect(position[:day_sell_qty]).to eq(DhanScalper::Support::Money.bd(0))
    end
  end
end
