# frozen_string_literal: true

require "spec_helper"

RSpec.describe DhanScalper::Services::MtmRefreshService do
  let(:balance_provider) { DhanScalper::BalanceProviders::PaperWallet.new(starting_balance: 100_000) }
  let(:position_tracker) { DhanScalper::Services::EnhancedPositionTracker.new }
  let(:equity_calculator) { DhanScalper::Services::EquityCalculator.new(balance_provider: balance_provider, position_tracker: position_tracker) }
  let(:mtm_service) { described_class.new(equity_calculator: equity_calculator) }
  let(:security_id) { "TEST123" }
  let(:exchange_segment) { "NSE_EQ" }

  before do
    # Mock tick cache for LTP
    allow(DhanScalper::TickCache).to receive(:ltp).and_return(100.0)
  end

  describe "#on_tick_received" do
    it "refreshes MTM when position exists" do
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

      # Simulate tick received
      mtm_service.on_tick_received(
        exchange_segment: exchange_segment,
        security_id: security_id,
        ltp: 120.0
      )

      # Check that position was updated
      position = position_tracker.get_position(
        exchange_segment: exchange_segment,
        security_id: security_id,
        side: "LONG"
      )

      expect(position[:current_price]).to eq(DhanScalper::Support::Money.bd(120.0))
      expect(position[:unrealized_pnl]).to eq(DhanScalper::Support::Money.bd(1_500)) # (120-100) * 75
    end

    it "ignores ticks for non-existent positions" do
      # No position created

      # Simulate tick received
      mtm_service.on_tick_received(
        exchange_segment: exchange_segment,
        security_id: "NONEXISTENT",
        ltp: 120.0
      )

      # Should not raise any errors
      expect(true).to be true
    end

    it "ignores ticks for positions with zero net quantity" do
      # Create a position and sell it all
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

      # Simulate tick received
      mtm_service.on_tick_received(
        exchange_segment: exchange_segment,
        security_id: security_id,
        ltp: 130.0
      )

      # Should not update anything since position is closed
      position = position_tracker.get_position(
        exchange_segment: exchange_segment,
        security_id: security_id,
        side: "LONG"
      )

      expect(position).to be_nil
    end

    it "respects refresh rate limiting" do
      # Create a position
      position_tracker.add_position(
        exchange_segment: exchange_segment,
        security_id: security_id,
        side: "LONG",
        quantity: 75,
        price: 100.0,
        fee: 20
      )

      # Set refresh interval to 2 seconds
      mtm_service.set_refresh_interval(2)

      # First tick should be processed
      mtm_service.on_tick_received(
        exchange_segment: exchange_segment,
        security_id: security_id,
        ltp: 120.0
      )

      # Second tick immediately should be ignored
      mtm_service.on_tick_received(
        exchange_segment: exchange_segment,
        security_id: security_id,
        ltp: 130.0
      )

      # Position should still have the first LTP
      position = position_tracker.get_position(
        exchange_segment: exchange_segment,
        security_id: security_id,
        side: "LONG"
      )

      expect(position[:current_price]).to eq(DhanScalper::Support::Money.bd(120.0))
    end
  end

  describe "#refresh_all_positions" do
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

      result = mtm_service.refresh_all_positions(ltp_provider: ltp_provider)

      expect(result[:success]).to be true
      expect(result[:total_unrealized]).to eq(DhanScalper::Support::Money.bd(500)) # 1000 - 500
      expect(result[:updated_positions].length).to eq(2)
    end

    it "refreshes all positions without LTP provider" do
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

      result = mtm_service.refresh_all_positions

      expect(result[:success]).to be true
      expect(result[:total_unrealized]).to eq(DhanScalper::Support::Money.bd(1_500))
    end
  end

  describe "#get_current_equity" do
    it "returns current equity calculation" do
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

      position_tracker.update_current_price(
        exchange_segment: exchange_segment,
        security_id: security_id,
        side: "LONG",
        current_price: 120.0
      )

      equity = mtm_service.get_current_equity

      expect(equity[:balance]).to eq(DhanScalper::Support::Money.bd(99_980))
      expect(equity[:unrealized_pnl]).to eq(DhanScalper::Support::Money.bd(1_500))
      expect(equity[:total_equity]).to eq(DhanScalper::Support::Money.bd(101_480))
    end
  end

  describe "#get_equity_breakdown" do
    it "returns detailed equity breakdown" do
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

      position_tracker.update_current_price(
        exchange_segment: exchange_segment,
        security_id: security_id,
        side: "LONG",
        current_price: 120.0
      )

      breakdown = mtm_service.get_equity_breakdown

      expect(breakdown[:total_equity]).to eq(DhanScalper::Support::Money.bd(101_480))
      expect(breakdown[:positions].length).to eq(1)
      expect(breakdown[:positions][0][:security_id]).to eq(security_id)
    end
  end

  describe "rate limiting" do
    it "allows setting custom refresh interval" do
      mtm_service.set_refresh_interval(5)
      expect(mtm_service.instance_variable_get(:@refresh_interval)).to eq(5)
    end

    it "clears refresh history" do
      mtm_service.clear_refresh_history
      expect(mtm_service.instance_variable_get(:@last_refresh)).to be_empty
    end
  end
end
