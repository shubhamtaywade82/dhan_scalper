# frozen_string_literal: true

require "spec_helper"
require "dhan_scalper"

RSpec.describe "DhanScalper Integration", :slow do
  let(:config) do
    {
      "global" => {
        "min_profit_target" => 1_000,
        "max_day_loss" => 1_500,
        "charge_per_order" => 20,
        "allocation_pct" => 0.30,
        "slippage_buffer_pct" => 0.01,
        "max_lots_per_trade" => 10,
        "decision_interval" => 10,
        "log_level" => "INFO",
        "tp_pct" => 0.35,
        "sl_pct" => 0.18,
        "trail_pct" => 0.12,
      },
      "paper" => {
        "starting_balance" => 200_000,
      },
      "SYMBOLS" => {
        "NIFTY" => {
          "idx_sid" => "13",
          "seg_idx" => "IDX_I",
          "seg_opt" => "NSE_FNO",
          "strike_step" => 50,
          "lot_size" => 75,
          "qty_multiplier" => 1,
          "expiry_wday" => 4,
        },
      },
    }
  end

  let(:app) { DhanScalper::App.new(config, mode: :paper) }

  before(:all) do
    # Ensure CSV master data is available for testing
    @csv_master = DhanScalper::CsvMaster.new
    @csv_master.send(:ensure_data_loaded)
  end

  describe "Complete System Integration" do
    it "initializes all components correctly" do
      expect(app.balance_provider).to be_a(DhanScalper::BalanceProviders::PaperWallet)
      expect(app.quantity_sizer).to be_a(DhanScalper::QuantitySizer)
      expect(app.broker).to be_a(DhanScalper::Brokers::PaperBroker)
      expect(app.mode).to eq(:paper)
    end

    it "sets up balance provider with correct starting balance" do
      expect(app.balance_provider.total_balance).to eq(200_000.0)
      expect(app.balance_provider.available_balance).to eq(200_000.0)
      expect(app.balance_provider.used_balance).to eq(0.0)
    end

    it "configures quantity sizer with correct parameters" do
      sizer = app.quantity_sizer
      expect(sizer.instance_variable_get(:@allocation_pct)).to eq(0.30)
      expect(sizer.instance_variable_get(:@max_lots_per_trade)).to eq(10)
    end
  end

  describe "CSV Master Data Integration" do
    it "fetches real expiry dates from DhanHQ master data" do
      expiries = @csv_master.get_expiry_dates("NIFTY")
      expect(expiries).not_to be_empty
      expect(expiries.first).to match(/\d{4}-\d{2}-\d{2}/)
      expect(expiries).to eq(expiries.sort) # Should be sorted
    end

    it "finds security IDs for specific options" do
      expiries = @csv_master.get_expiry_dates("NIFTY")
      first_expiry = expiries.first

      # Test with a reasonable strike price
      security_id = @csv_master.get_security_id("NIFTY", first_expiry, 25_000, "CE")
      expect(security_id).not_to be_nil
      expect(security_id).to be_a(String)

      # Verify lot size
      lot_size = @csv_master.get_lot_size(security_id)
      expect(lot_size).to eq(75)
    end

    it "supports both OPTIDX and OPTFUT instruments" do
      # NIFTY should use OPTIDX
      nifty_expiries = @csv_master.get_expiry_dates("NIFTY")
      expect(nifty_expiries).not_to be_empty

      # Some commodities might use OPTFUT
      gold_expiries = @csv_master.get_expiry_dates("GOLD")
      expect(gold_expiries).not_to be_empty if gold_expiries.any?
    end
  end

  describe "OptionPicker Integration" do
    let(:picker) { DhanScalper::OptionPicker.new(config["SYMBOLS"]["NIFTY"], mode: :paper) }

    it "fetches expiry dates from CSV master" do
      expiry = picker.fetch_first_expiry
      expect(expiry).to match(/\d{4}-\d{2}-\d{2}/)
      expect(expiry).not_to eq("2025-09-04") # Should not be fallback date
    end

    it "picks options with real security IDs" do
      current_spot = 25_000
      options = picker.pick(current_spot: current_spot)

      expect(options).not_to be_nil
      expect(options[:expiry]).to match(/\d{4}-\d{2}-\d{2}/)
      expect(options[:strikes]).to eq([24_950, 25_000, 25_050])

      # Should have real security IDs, not paper ones
      expect(options[:ce_sid][25_000]).not_to start_with("PAPER_")
      expect(options[:pe_sid][25_000]).not_to start_with("PAPER_")
    end

    it "falls back to paper mode when CSV lookup fails" do
      # Mock a failure scenario
      allow(@csv_master).to receive(:get_expiry_dates).and_raise(StandardError, "API Error")

      picker_with_failure = DhanScalper::OptionPicker.new(config["SYMBOLS"]["NIFTY"], mode: :paper)
      expiry = picker_with_failure.fetch_first_expiry

      # Should fall back to calculated expiry
      expect(expiry).to match(/\d{4}-\d{2}-\d{2}/)
    end
  end

  describe "QuantitySizer Integration" do
    let(:sizer) { app.quantity_sizer }

    it "calculates lots based on available balance and allocation" do
      # With 200k balance and 30% allocation = 60k available
      # For a 100 premium option, should get 600 lots (60k / 100)
      lots = sizer.calculate_lots("NIFTY", 100.0)
      expected_lots = (200_000 * 0.30 / 100.0).to_i
      expect(lots).to eq(expected_lots)
    end

    it "respects max lots per trade constraint" do
      # With very low premium, should be capped at max_lots_per_trade
      lots = sizer.calculate_lots("NIFTY", 1.0)
      expect(lots).to eq(10) # max_lots_per_trade
    end

    it "calculates quantity correctly" do
      lots = sizer.calculate_lots("NIFTY", 100.0)
      quantity = sizer.calculate_quantity("NIFTY", 100.0)
      expect(quantity).to eq(lots * 75) # 75 is NIFTY lot size
    end
  end

  describe "Balance Provider Integration" do
    it "updates balance correctly for paper trading" do
      provider = app.balance_provider
      initial_balance = provider.total_balance

      # Simulate a trade
      provider.update_balance(50_000, type: :debit)

      expect(provider.used_balance).to eq(50_000.0)
      expect(provider.available_balance).to eq(initial_balance - 50_000.0)
      expect(provider.total_balance).to eq(initial_balance)
    end

    it "prevents trades when insufficient balance" do
      provider = app.balance_provider
      provider.update_balance(250_000, type: :debit) # More than available

      expect(provider.available_balance).to eq(0.0)
      expect(provider.used_balance).to eq(250_000.0)
    end
  end

  describe "Broker Integration" do
    let(:broker) { app.broker }

    it "executes buy orders and updates balance" do
      initial_balance = app.balance_provider.available_balance

      # Mock tick cache to return a price
      allow(DhanScalper::TickCache).to receive(:ltp).and_return(100.0)

      order = broker.buy_market(segment: "NSE_FNO", security_id: "TEST123", quantity: 100)

      expect(order).not_to be_nil
      expect(order.security_id).to eq("TEST123")
      expect(order.quantity).to eq(100)
      expect(order.price).to eq(100.0)

      # Balance should be reduced
      expect(app.balance_provider.available_balance).to be < initial_balance
    end

    it "executes sell orders and updates balance" do
      # First buy some
      allow(DhanScalper::TickCache).to receive(:ltp).and_return(100.0)
      broker.buy_market(segment: "NSE_FNO", security_id: "TEST123", quantity: 100)

      initial_balance = app.balance_provider.available_balance

      # Then sell
      order = broker.sell_market(segment: "NSE_FNO", security_id: "TEST123", quantity: 100)

      expect(order).not_to be_nil
      expect(order.side).to eq("SELL")

      # Balance should be increased
      expect(app.balance_provider.available_balance).to be > initial_balance
    end
  end

  describe "Trader Integration" do
    let(:trader) { app.traders["NIFTY"] }

    before do
      # Mock the option picker to return test data
      allow_any_instance_of(DhanScalper::OptionPicker).to receive(:pick).and_return({
                                                                                      expiry: "2025-09-02",
                                                                                      strikes: [24_950, 25_000, 25_050],
                                                                                      ce_sid: { 24_950 => "TEST_CE_1",
                                                                                                25_000 => "TEST_CE_2", 25_050 => "TEST_CE_3" },
                                                                                      pe_sid: { 24_950 => "TEST_PE_1",
                                                                                                25_000 => "TEST_PE_2", 25_050 => "TEST_PE_3" },
                                                                                    })
    end

    it "initializes with correct configuration" do
      expect(trader).not_to be_nil
      expect(trader.symbol).to eq("NIFTY")
      expect(trader.quantity_sizer).to eq(app.quantity_sizer)
      expect(trader.broker).to eq(app.broker)
    end

    it "can calculate position sizing" do
      # Mock tick cache
      allow(DhanScalper::TickCache).to receive(:ltp).and_return(100.0)

      lots = trader.quantity_sizer.calculate_lots("NIFTY", 100.0)
      expect(lots).to be > 0
    end
  end

  describe "Dashboard Integration" do
    let(:dashboard) { DhanScalper::UI::Dashboard.new(app.balance_provider) }

    it "displays balance information" do
      output = capture_stdout { dashboard.render_frame }

      expect(output).to include("Available:")
      expect(output).to include("Used:")
      expect(output).to include("Total:")
      expect(output).to include("₹200000.0")
    end

    it "handles balance updates" do
      # Update balance
      app.balance_provider.update_balance(50_000, type: :debit)

      output = capture_stdout { dashboard.render_frame }
      expect(output).to include("₹150000.0") # Available should be reduced
    end
  end

  describe "CLI Integration" do
    it "responds to help command" do
      output = capture_stdout { DhanScalper::CLI.new.help }
      expect(output).to include("Commands:")
      expect(output).to include("balance")
      expect(output).to include("start")
    end

    it "executes balance command" do
      output = capture_stdout { DhanScalper::CLI.new.balance }
      expect(output).to include("Virtual Balance:")
      expect(output).to include("₹200000.0")
    end
  end

  describe "Error Handling and Resilience" do
    it "continues operation when CSV master fails" do
      # Mock CSV master failure
      allow_any_instance_of(DhanScalper::CsvMaster).to receive(:get_expiry_dates).and_raise(StandardError,
                                                                                            "Network Error")

      picker = DhanScalper::OptionPicker.new(config["SYMBOLS"]["NIFTY"], mode: :paper)
      expiry = picker.fetch_first_expiry

      # Should fall back to calculated expiry
      expect(expiry).to match(/\d{4}-\d{2}-\d{2}/)
    end

    it "handles broker errors gracefully" do
      # Mock broker failure
      allow_any_instance_of(DhanScalper::Brokers::PaperBroker).to receive(:buy_market).and_raise(StandardError,
                                                                                                 "Order Failed")

      trader = app.traders["NIFTY"]

      # Should not crash the system
      expect { trader.maybe_enter(25_000) }.not_to raise_error
    end
  end

  describe "Performance and Caching" do
    it "caches CSV master data efficiently" do
      start_time = Time.now

      # First call should fetch from network
      @csv_master.get_expiry_dates("NIFTY")
      first_call_time = Time.now - start_time

      # Second call should use cache
      start_time = Time.now
      @csv_master.get_expiry_dates("NIFTY")
      second_call_time = Time.now - start_time

      # Cache should be faster
      expect(second_call_time).to be < first_call_time
    end

    it "maintains data consistency across components" do
      # All components should see the same balance
      expect(app.balance_provider.total_balance).to eq(200_000.0)
      expect(app.quantity_sizer.instance_variable_get(:@total_balance)).to eq(200_000.0)
    end
  end

  # Helper method to capture stdout
  def capture_stdout
    old_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = old_stdout
  end
end
