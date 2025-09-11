# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Equity Calculation Acceptance Criteria" do
  let(:balance_provider) { DhanScalper::BalanceProviders::PaperWallet.new(starting_balance: 100_000) }
  let(:position_tracker) { DhanScalper::Services::EnhancedPositionTracker.new }
  let(:equity_calculator) { DhanScalper::Services::EquityCalculator.new(balance_provider: balance_provider, position_tracker: position_tracker) }
  let(:mtm_service) { DhanScalper::Services::MtmRefreshService.new(equity_calculator: equity_calculator) }
  let(:security_id) { "TEST123" }
  let(:exchange_segment) { "NSE_EQ" }

  before do
    # Mock tick cache for LTP
    allow(DhanScalper::TickCache).to receive(:ltp).and_return(100.0)
  end

  # Helper method to debit balance for position costs
  def debit_balance_for_position(balance_provider, quantity, price, fee)
    total_cost = (quantity * price) + fee
    new_total = DhanScalper::Support::Money.subtract(balance_provider.total_balance, DhanScalper::Support::Money.bd(total_cost))
    balance_provider.instance_variable_set(:@total, new_total)
    balance_provider.instance_variable_set(:@available, new_total)
  end

  describe "Acceptance Criteria: Buy @100, LTP @120, 75 units" do
    it "calculates correct unrealized PnL and equity" do
      # Step 1: Buy 75 units @ ₹100
      # Simulate balance update (normally done by broker)
      debit_balance_for_position(balance_provider, 75, 100.0, 20)

      position_tracker.add_position(
        exchange_segment: exchange_segment,
        security_id: security_id,
        side: "LONG",
        quantity: 75,
        price: 100.0,
        fee: 20
      )

      # Verify initial state
      initial_equity = equity_calculator.calculate_equity
      expect(initial_equity[:balance]).to eq(DhanScalper::Support::Money.bd(92_480)) # 100000 - 7520
      expect(initial_equity[:unrealized_pnl]).to eq(DhanScalper::Support::Money.bd(0)) # No unrealized yet
      expect(initial_equity[:total_equity]).to eq(DhanScalper::Support::Money.bd(92_480))

      # Step 2: LTP moves to ₹120
      mtm_service.on_tick_received(
        exchange_segment: exchange_segment,
        security_id: security_id,
        ltp: 120.0
      )

      # Verify final state
      final_equity = equity_calculator.calculate_equity
      expect(final_equity[:balance]).to eq(DhanScalper::Support::Money.bd(92_480)) # Balance unchanged
      expect(final_equity[:unrealized_pnl]).to eq(DhanScalper::Support::Money.bd(1_500)) # (120-100) * 75
      expect(final_equity[:total_equity]).to eq(DhanScalper::Support::Money.bd(93_980)) # 92480 + 1500

      # Verify position details
      position = position_tracker.get_position(
        exchange_segment: exchange_segment,
        security_id: security_id,
        side: "LONG"
      )

      expect(position[:net_qty]).to eq(DhanScalper::Support::Money.bd(75))
      expect(position[:buy_avg]).to eq(DhanScalper::Support::Money.bd(100.0))
      expect(position[:current_price]).to eq(DhanScalper::Support::Money.bd(120.0))
      expect(position[:unrealized_pnl]).to eq(DhanScalper::Support::Money.bd(1_500))
    end

    it "maintains correct equity through multiple LTP updates" do
      # Create position
      # Simulate balance update
      debit_balance_for_position(balance_provider, 75, 100.0, 20)

      position_tracker.add_position(
        exchange_segment: exchange_segment,
        security_id: security_id,
        side: "LONG",
        quantity: 75,
        price: 100.0,
        fee: 20
      )

      # Disable rate limiting for this test
      mtm_service.set_refresh_interval(0)

      # LTP updates
      ltp_updates = [110.0, 120.0, 115.0, 125.0]
      expected_unrealized = [750, 1500, 1125, 1875] # (ltp - 100) * 75

      ltp_updates.each_with_index do |ltp, index|
        mtm_service.on_tick_received(
          exchange_segment: exchange_segment,
          security_id: security_id,
          ltp: ltp
        )

        equity = equity_calculator.calculate_equity
        expect(equity[:unrealized_pnl]).to eq(DhanScalper::Support::Money.bd(expected_unrealized[index]))
        expect(equity[:total_equity]).to eq(DhanScalper::Support::Money.bd(92_480 + expected_unrealized[index]))
      end
    end

    it "handles negative unrealized PnL correctly" do
      # Create position
      # Simulate balance update
      debit_balance_for_position(balance_provider, 75, 100.0, 20)

      position_tracker.add_position(
        exchange_segment: exchange_segment,
        security_id: security_id,
        side: "LONG",
        quantity: 75,
        price: 100.0,
        fee: 20
      )

      # LTP drops to ₹80
      mtm_service.on_tick_received(
        exchange_segment: exchange_segment,
        security_id: security_id,
        ltp: 80.0
      )

      equity = equity_calculator.calculate_equity
      expect(equity[:balance]).to eq(DhanScalper::Support::Money.bd(92_480))
      expect(equity[:unrealized_pnl]).to eq(DhanScalper::Support::Money.bd(-1_500)) # (80-100) * 75
      expect(equity[:total_equity]).to eq(DhanScalper::Support::Money.bd(90_980)) # 92480 - 1500
    end

    it "integrates with tick loop simulation" do
      # Create position
      # Simulate balance update
      debit_balance_for_position(balance_provider, 75, 100.0, 20)

      position_tracker.add_position(
        exchange_segment: exchange_segment,
        security_id: security_id,
        side: "LONG",
        quantity: 75,
        price: 100.0,
        fee: 20
      )

      # Disable rate limiting for this test
      mtm_service.set_refresh_interval(0)

      # Simulate tick loop with multiple securities
      tick_data = [
        { security_id: "TEST123", ltp: 120.0 },
        { security_id: "TEST456", ltp: 150.0 }, # No position, should be ignored
        { security_id: "TEST123", ltp: 125.0 },
        { security_id: "TEST123", ltp: 115.0 }
      ]

      tick_data.each do |tick|
        mtm_service.on_tick_received(
          exchange_segment: exchange_segment,
          security_id: tick[:security_id],
          ltp: tick[:ltp]
        )
      end

      # Final equity should reflect last LTP
      final_equity = equity_calculator.calculate_equity
      expect(final_equity[:unrealized_pnl]).to eq(DhanScalper::Support::Money.bd(1_125)) # (115-100) * 75
      expect(final_equity[:total_equity]).to eq(DhanScalper::Support::Money.bd(93_605)) # 92480 + 1125
    end
  end

  describe "Multiple positions scenario" do
    it "calculates equity correctly with multiple positions" do
      # Create multiple positions
      # Simulate balance updates
      debit_balance_for_position(balance_provider, 50, 100.0, 20)
      debit_balance_for_position(balance_provider, 25, 200.0, 20)

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

      # Update LTPs
      mtm_service.on_tick_received(exchange_segment: exchange_segment, security_id: "TEST123", ltp: 120.0)
      mtm_service.on_tick_received(exchange_segment: exchange_segment, security_id: "TEST456", ltp: 180.0)

      equity = equity_calculator.calculate_equity

      # TEST123: (120-100) * 50 = 1000 unrealized
      # TEST456: (180-200) * 25 = -500 unrealized
      # Total unrealized: 1000 - 500 = 500
      # Total cost: (50*100 + 20) + (25*200 + 20) = 5020 + 5020 = 10040
      # Balance: 100000 - 10040 = 89960
      expect(equity[:unrealized_pnl]).to eq(DhanScalper::Support::Money.bd(500))
      expect(equity[:total_equity]).to eq(DhanScalper::Support::Money.bd(90_460)) # 89960 + 500
    end
  end
end
