# frozen_string_literal: true

require "spec_helper"
require "bigdecimal"

RSpec.describe "Paper Broker Smoke Tests" do
  let(:config) { DhanScalper::Config.load(path: "config/scalper.paper.yml") }
  let(:balance_provider) do
    DhanScalper::BalanceProviders::PaperWallet.new(
      starting_balance: config.dig("paper", "starting_balance") || 100_000.0
    )
  end
  let(:position_tracker) do
    DhanScalper::Services::EnhancedPositionTracker.new
  end
  let(:broker) do
    DhanScalper::Brokers::PaperBroker.new(
      virtual_data_manager: nil,
      balance_provider: balance_provider,
      logger: Logger.new($stdout)
    )
  end

  before do
    # Clear tick cache and reset state
    DhanScalper::TickCache.clear
    balance_provider.reset_balance(100_000.0)
    position_tracker.instance_variable_set(:@positions, {})
    position_tracker.instance_variable_set(:@realized_pnl, DhanScalper::Support::Money.bd(0))

    # Seed initial LTP
    DhanScalper::TickCache.put({
      segment: "NSE_FNO",
      security_id: "TEST_CE_100",
      ltp: 100.0,
      timestamp: Time.now.to_i
    })
  end

  describe "profit round trip" do
    it "should execute BUY 75 @100 → SELL 75 @120 correctly" do
      # BUY 75 @100
      buy_result = broker.buy_market(
        segment: "NSE_FNO",
        security_id: "TEST_CE_100",
        quantity: 75,
        charge_per_order: 20
      )

      expect(buy_result).not_to be_a(Hash)

      # Update LTP to 120 for profit
      DhanScalper::TickCache.put({
        segment: "NSE_FNO",
        security_id: "TEST_CE_100",
        ltp: 120.0,
        timestamp: Time.now.to_i
      })

      # SELL 75 @120
      sell_result = broker.sell_market(
        segment: "NSE_FNO",
        security_id: "TEST_CE_100",
        quantity: 75,
        charge_per_order: 20
      )

      expect(sell_result).not_to be_a(Hash)

      # Verify final balance
      final_balance = balance_provider.total_balance
      expected_balance = 101_460.0 # 100000 + (20*75) - (20*2)

      expect(final_balance).to be_within(0.01).of(expected_balance)
    end
  end

  describe "loss round trip" do
    it "should execute BUY 75 @100 → SELL 75 @90 correctly" do
      # BUY 75 @100
      buy_result = broker.buy_market(
        segment: "NSE_FNO",
        security_id: "TEST_CE_100",
        quantity: 75,
        charge_per_order: 20
      )

      expect(buy_result).not_to be_a(Hash)

      # Update LTP to 90 for loss
      DhanScalper::TickCache.put({
        segment: "NSE_FNO",
        security_id: "TEST_CE_100",
        ltp: 90.0,
        timestamp: Time.now.to_i
      })

      # SELL 75 @90
      sell_result = broker.sell_market(
        segment: "NSE_FNO",
        security_id: "TEST_CE_100",
        quantity: 75,
        charge_per_order: 20
      )

      expect(sell_result).not_to be_a(Hash)

      # Verify final balance
      final_balance = balance_provider.total_balance
      expected_balance = 99_210.0 # 100000 - (10*75) - (20*2)

      expect(final_balance).to be_within(0.01).of(expected_balance)
    end
  end

  describe "partial exit / averaging" do
    it "should handle BUY 75 @100 → BUY 75 @120 → SELL 75 @130 correctly" do
      # BUY 75 @100
      buy1_result = broker.buy_market(
        segment: "NSE_FNO",
        security_id: "TEST_CE_100",
        quantity: 75,
        charge_per_order: 20
      )

      expect(buy1_result).not_to be_a(Hash)

      # Update LTP to 120
      DhanScalper::TickCache.put({
        segment: "NSE_FNO",
        security_id: "TEST_CE_100",
        ltp: 120.0,
        timestamp: Time.now.to_i
      })

      # BUY 75 @120 (averaging)
      buy2_result = broker.buy_market(
        segment: "NSE_FNO",
        security_id: "TEST_CE_100",
        quantity: 75,
        charge_per_order: 20
      )

      expect(buy2_result).not_to be_a(Hash)

      # Update LTP to 130
      DhanScalper::TickCache.put({
        segment: "NSE_FNO",
        security_id: "TEST_CE_100",
        ltp: 130.0,
        timestamp: Time.now.to_i
      })

      # SELL 75 @130 (partial exit)
      sell_result = broker.sell_market(
        segment: "NSE_FNO",
        security_id: "TEST_CE_100",
        quantity: 75,
        charge_per_order: 20
      )

      expect(sell_result).not_to be_a(Hash)

      # Verify final balance
      final_balance = balance_provider.total_balance
      expected_balance = 99_190.0 # 100000 - (100*75) - (120*75) + (130*75) - (20*3)

      expect(final_balance).to be_within(0.01).of(expected_balance)
    end
  end

  describe "insufficient funds rejection" do
    it "should reject BUY when balance is insufficient" do
      # Set tiny balance
      balance_provider.reset_balance(5_000.0)

      # Attempt BUY 75 @100 (should fail)
      buy_result = broker.buy_market(
        segment: "NSE_FNO",
        security_id: "TEST_CE_100",
        quantity: 75,
        charge_per_order: 20
      )

      expect(buy_result).to be_a(Hash)
      expect(buy_result[:success]).to be false
      expect(buy_result[:error]).to include("insufficient")
    end
  end

  describe "oversell rejection" do
    it "should reject SELL when quantity exceeds position" do
      # BUY 75 @100
      buy_result = broker.buy_market(
        segment: "NSE_FNO",
        security_id: "TEST_CE_100",
        quantity: 75,
        charge_per_order: 20
      )

      expect(buy_result).not_to be_a(Hash)

      # Attempt SELL 150 (should fail - oversell)
      sell_result = broker.sell_market(
        segment: "NSE_FNO",
        security_id: "TEST_CE_100",
        quantity: 150,
        charge_per_order: 20
      )

      expect(sell_result).to be_a(Hash)
      expect(sell_result[:success]).to be false
      expect(sell_result[:error]).to include("insufficient")
    end
  end

  describe "equity invariant" do
    it "should have equity equal to balance when flat" do
      balance = balance_provider.total_balance
      positions = position_tracker.get_positions

      expect(positions).to be_empty
      expect(balance).to eq(100_000.0)
    end
  end
end
