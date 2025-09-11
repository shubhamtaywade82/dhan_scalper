# frozen_string_literal: true

require "spec_helper"

RSpec.describe DhanScalper::Services::EquityCalculator do
  let(:balance_provider) { DhanScalper::BalanceProviders::PaperWallet.new(starting_balance: 100_000) }
  let(:position_tracker) { DhanScalper::Services::EnhancedPositionTracker.new }
  let(:equity_calculator) { described_class.new(balance_provider: balance_provider, position_tracker: position_tracker) }
  let(:security_id) { "TEST123" }
  let(:exchange_segment) { "NSE_EQ" }

  before do
    # Mock tick cache for LTP
    allow(DhanScalper::TickCache).to receive(:ltp).and_return(100.0)
  end

  describe "#calculate_equity" do
    it "calculates equity as balance + unrealized PnL" do
      # Create a position
      # Simulate balance update
      total_cost = (75 * 100.0) + 20.0
      balance_provider.update_balance(total_cost, type: :debit)

      position_tracker.add_position(
        exchange_segment: exchange_segment,
        security_id: security_id,
        side: "LONG",
        quantity: 75,
        price: 100.0,
        fee: 20
      )

      # Set current price to 120
      position_tracker.update_current_price(
        exchange_segment: exchange_segment,
        security_id: security_id,
        side: "LONG",
        current_price: 120.0
      )

      equity = equity_calculator.calculate_equity

      expect(equity[:balance]).to eq(DhanScalper::Support::Money.bd(99_980)) # 100000 - 7520 (75*100 + 20)
      expect(equity[:unrealized_pnl]).to eq(DhanScalper::Support::Money.bd(1_500)) # (120-100) * 75
      expect(equity[:total_equity]).to eq(DhanScalper::Support::Money.bd(101_480)) # 99980 + 1500
    end

    it "handles multiple positions" do
      # Create two positions
      # Simulate balance updates
      total_cost_1 = (50 * 100.0) + 20.0
      total_cost_2 = (25 * 200.0) + 20.0
      balance_provider.update_balance(total_cost_1, type: :debit)
      balance_provider.update_balance(total_cost_2, type: :debit)

      position_tracker.add_position(
        exchange_segment: exchange_segment,
        security_id: "TEST123",
        side: "LONG",
        quantity: 50,
        price: 100.0,
        fee: 20
      )

      position_tracker.add_position(
        exchange_segment: exchange_segment,
        security_id: "TEST456",
        side: "LONG",
        quantity: 25,
        price: 200.0,
        fee: 20
      )

      # Set current prices
      position_tracker.update_current_price(
        exchange_segment: exchange_segment,
        security_id: "TEST123",
        side: "LONG",
        current_price: 120.0
      )

      position_tracker.update_current_price(
        exchange_segment: exchange_segment,
        security_id: "TEST456",
        side: "LONG",
        current_price: 180.0
      )

      equity = equity_calculator.calculate_equity

      # TEST123: (120-100) * 50 = 1000 unrealized
      # TEST456: (180-200) * 25 = -500 unrealized
      # Total unrealized: 1000 - 500 = 500
      expect(equity[:unrealized_pnl]).to eq(DhanScalper::Support::Money.bd(500))
    end

    it "ignores positions with zero net quantity" do
      # Create a position and then sell it all
      # Simulate balance update
      total_cost = (75 * 100.0) + 20.0
      balance_provider.update_balance(total_cost, type: :debit)

      position_tracker.add_position(
        exchange_segment: exchange_segment,
        security_id: security_id,
        side: "LONG",
        quantity: 75,
        price: 100.0,
        fee: 20
      )

      position_tracker.partial_exit(
        exchange_segment: exchange_segment,
        security_id: security_id,
        side: "LONG",
        quantity: 75,
        price: 120.0,
        fee: 20
      )

      equity = equity_calculator.calculate_equity

      # No unrealized PnL since position is closed
      expect(equity[:unrealized_pnl]).to eq(DhanScalper::Support::Money.bd(0))
    end
  end

  describe "#refresh_unrealized!" do
    it "refreshes unrealized PnL for a specific position" do
      # Create a position
      position_tracker.add_position(
        exchange_segment: exchange_segment,
        security_id: security_id,
        side: "LONG",
        quantity: 75,
        price: 100.0,
        fee: 20
      )

      result = equity_calculator.refresh_unrealized!(
        exchange_segment: exchange_segment,
        security_id: security_id,
        current_ltp: 120.0
      )

      expect(result[:success]).to be true
      expect(result[:unrealized_pnl]).to eq(DhanScalper::Support::Money.bd(1_500)) # (120-100) * 75
      expect(result[:current_ltp]).to eq(DhanScalper::Support::Money.bd(120.0))
      expect(result[:net_qty]).to eq(DhanScalper::Support::Money.bd(75))
      expect(result[:buy_avg]).to eq(DhanScalper::Support::Money.bd(100.0))
    end

    it "returns error for non-existent position" do
      result = equity_calculator.refresh_unrealized!(
        exchange_segment: exchange_segment,
        security_id: "NONEXISTENT",
        current_ltp: 120.0
      )

      expect(result[:success]).to be false
      expect(result[:error]).to eq("Position not found")
    end

    it "handles negative unrealized PnL" do
      # Create a position
      position_tracker.add_position(
        exchange_segment: exchange_segment,
        security_id: security_id,
        side: "LONG",
        quantity: 75,
        price: 100.0,
        fee: 20
      )

      result = equity_calculator.refresh_unrealized!(
        exchange_segment: exchange_segment,
        security_id: security_id,
        current_ltp: 80.0
      )

      expect(result[:success]).to be true
      expect(result[:unrealized_pnl]).to eq(DhanScalper::Support::Money.bd(-1_500)) # (80-100) * 75
    end
  end

  describe "#refresh_all_unrealized!" do
    it "refreshes all positions with LTP provider" do
      # Create positions
      position_tracker.add_position(
        exchange_segment: exchange_segment,
        security_id: "TEST123",
        side: "LONG",
        quantity: 50,
        price: 100.0,
        fee: 20
      )

      position_tracker.add_position(
        exchange_segment: exchange_segment,
        security_id: "TEST456",
        side: "LONG",
        quantity: 25,
        price: 200.0,
        fee: 20
      )

      # Mock LTP provider
      ltp_provider = lambda do |segment, security_id|
        case security_id
        when "TEST123" then 120.0
        when "TEST456" then 180.0
        else nil
        end
      end

      result = equity_calculator.refresh_all_unrealized!(ltp_provider: ltp_provider)

      expect(result[:success]).to be true
      expect(result[:total_unrealized]).to eq(DhanScalper::Support::Money.bd(500)) # 1000 - 500
      expect(result[:updated_positions].length).to eq(2)
    end

    it "handles positions without LTP provider" do
      # Create a position
      position_tracker.add_position(
        exchange_segment: exchange_segment,
        security_id: security_id,
        side: "LONG",
        quantity: 75,
        price: 100.0,
        fee: 20
      )

      # Set current price
      position_tracker.update_current_price(
        exchange_segment: exchange_segment,
        security_id: security_id,
        side: "LONG",
        current_price: 120.0
      )

      result = equity_calculator.refresh_all_unrealized!

      expect(result[:success]).to be true
      expect(result[:total_unrealized]).to eq(DhanScalper::Support::Money.bd(1_500))
    end
  end

  describe "#get_equity_breakdown" do
    it "provides detailed equity breakdown" do
      # Create a position
      position_tracker.add_position(
        exchange_segment: exchange_segment,
        security_id: security_id,
        side: "LONG",
        quantity: 75,
        price: 100.0,
        fee: 20
      )

      position_tracker.update_current_price(
        exchange_segment: exchange_segment,
        security_id: security_id,
        side: "LONG",
        current_price: 120.0
      )

      breakdown = equity_calculator.get_equity_breakdown

      expect(breakdown[:starting_balance]).to eq(DhanScalper::Support::Money.bd(100_000))
      expect(breakdown[:available_balance]).to eq(DhanScalper::Support::Money.bd(99_980))
      expect(breakdown[:used_balance]).to eq(DhanScalper::Support::Money.bd(7_520))
      expect(breakdown[:total_balance]).to eq(DhanScalper::Support::Money.bd(99_980))
      expect(breakdown[:unrealized_pnl]).to eq(DhanScalper::Support::Money.bd(1_500))
      expect(breakdown[:total_equity]).to eq(DhanScalper::Support::Money.bd(101_480))
      expect(breakdown[:positions].length).to eq(1)
      expect(breakdown[:positions][0][:security_id]).to eq(security_id)
      expect(breakdown[:positions][0][:unrealized_pnl]).to eq(DhanScalper::Support::Money.bd(1_500))
    end
  end
end
