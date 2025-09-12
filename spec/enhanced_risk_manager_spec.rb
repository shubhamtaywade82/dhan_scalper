# frozen_string_literal: true

require "spec_helper"

RSpec.describe DhanScalper::EnhancedRiskManager do
  let(:config) do
    {
      "global" => {
        "tp_pct" => 0.35,
        "sl_pct" => 0.18,
        "trail_pct" => 0.12,
        "charge_per_order" => 20.0,
        "risk_check_interval" => 1,
        "time_stop_seconds" => 5, # Short for testing
        "max_daily_loss_rs" => 1_000.0,
        "cooldown_after_loss_seconds" => 3, # Short for testing
        "enable_time_stop" => true,
        "enable_daily_loss_cap" => true,
        "enable_cooldown" => true,
      },
    }
  end

  let(:position_tracker) { DhanScalper::Services::EnhancedPositionTracker.new }
  let(:balance_provider) { DhanScalper::BalanceProviders::PaperWallet.new(starting_balance: 100_000) }
  let(:equity_calculator) { DhanScalper::Services::EquityCalculator.new(balance_provider: balance_provider, position_tracker: position_tracker) }
  let(:broker) { double("Broker") }
  let(:risk_manager) { described_class.new(config, position_tracker, broker, balance_provider, equity_calculator) }

  before do
    # Mock tick cache
    allow(DhanScalper::TickCache).to receive(:ltp).and_return(100.0)

    # Mock broker responses
    allow(broker).to receive(:place_order!).and_return({ order_status: "FILLED", order_id: "test_order_123" })

    # Reset position tracker and balance provider for each test
    # Skip this for the daily loss cap test as it uses fresh instances
    unless caller.any? { |line| line.include?("closes all positions when daily loss cap is exceeded") }
      position_tracker.instance_variable_set(:@positions, {})
      position_tracker.instance_variable_set(:@realized_pnl, DhanScalper::Support::Money.bd(0))
      balance_provider.instance_variable_set(:@total, DhanScalper::Support::Money.bd(100_000))
      balance_provider.instance_variable_set(:@available, DhanScalper::Support::Money.bd(100_000))
    end
  end

  describe "#initialize" do
    it "initializes with correct configuration" do
      expect(risk_manager.instance_variable_get(:@time_stop_seconds)).to eq(5)
      expect(risk_manager.instance_variable_get(:@max_daily_loss_rs)).to eq(DhanScalper::Support::Money.bd(1_000.0))
      expect(risk_manager.instance_variable_get(:@cooldown_after_loss_seconds)).to eq(3)
      expect(risk_manager.instance_variable_get(:@enable_time_stop)).to be true
      expect(risk_manager.instance_variable_get(:@enable_daily_loss_cap)).to be true
      expect(risk_manager.instance_variable_get(:@enable_cooldown)).to be true
    end
  end

  describe "#start" do
    it "starts the risk management loop" do
      risk_manager.start
      expect(risk_manager.running?).to be true
      risk_manager.stop
    end

    it "initializes session tracking" do
      risk_manager.start
      expect(risk_manager.instance_variable_get(:@session_start_equity)).to eq(equity_calculator.calculate_equity[:total_equity])
      risk_manager.stop
    end
  end

  describe "Time Stop" do
    it "exits position after time stop period" do
      # Create a position
      position_tracker.add_position(
        exchange_segment: "NSE_EQ",
        security_id: "TEST123",
        side: "LONG",
        quantity: 75,
        price: 100.0,
      )

      position_tracker.get_position(
        exchange_segment: "NSE_EQ",
        security_id: "TEST123",
        side: "LONG",
      )

      # Mock entry time to be past the time stop threshold
      entry_time = Time.now - 6 # 6 seconds ago (past 5 second threshold)
      risk_manager.instance_variable_get(:@position_entry_times)["TEST123"] = entry_time

      # Start risk manager
      risk_manager.start

      # Wait a bit for the risk loop to run
      sleep(0.1)

      # Verify exit order was placed
      expect(broker).to have_received(:place_order!).with(
        symbol: "TEST123",
        instrument_id: "TEST123",
        side: "SELL",
        quantity: 75,
        price: 100.0,
        order_type: "MARKET",
        idempotency_key: match(/risk_exit_TEST123_TIME_STOP_/),
      )

      risk_manager.stop
    end

    it "does not exit position before time stop period" do
      # Create a position
      position_tracker.add_position(
        exchange_segment: "NSE_EQ",
        security_id: "TEST123",
        side: "LONG",
        quantity: 75,
        price: 100.0,
      )

      # Mock entry time to be within the time stop threshold
      entry_time = Time.now - 2 # 2 seconds ago (within 5 second threshold)
      risk_manager.instance_variable_get(:@position_entry_times)["TEST123"] = entry_time

      # Start risk manager
      risk_manager.start

      # Wait a bit for the risk loop to run
      sleep(0.1)

      # Verify no exit order was placed
      expect(broker).not_to have_received(:place_order!)

      risk_manager.stop
    end
  end

  describe "Daily Loss Cap" do
    it "closes all positions when daily loss cap is exceeded" do
      # Create fresh broker mock for this test
      broker_mock = double("Broker")
      allow(broker_mock).to receive(:place_order!).and_return({ order_status: "FILLED", order_id: "test_order_123" })

      # Create fresh balance provider, position tracker and risk manager
      fresh_balance_provider = DhanScalper::BalanceProviders::PaperWallet.new(starting_balance: 100_000)
      fresh_position_tracker = DhanScalper::Services::EnhancedPositionTracker.new
      fresh_equity_calculator = DhanScalper::Services::EquityCalculator.new(balance_provider: fresh_balance_provider, position_tracker: fresh_position_tracker)
      risk_mgr = described_class.new(config, fresh_position_tracker, broker_mock, fresh_balance_provider, fresh_equity_calculator)

      # Set session start equity to 100,000
      risk_mgr.reset_session

      # Create positions with same entry price to avoid stop loss triggers
      fresh_position_tracker.add_position(
        exchange_segment: "NSE_EQ",
        security_id: "TEST123",
        side: "LONG",
        quantity: 75,
        price: 100.0,
      )

      fresh_position_tracker.add_position(
        exchange_segment: "NSE_EQ",
        security_id: "TEST456",
        side: "LONG",
        quantity: 50,
        price: 100.0, # Same price to avoid stop loss
      )

      # Simulate a large loss by reducing balance significantly
      # This should trigger daily loss cap, not individual position stop loss
      fresh_balance_provider.instance_variable_set(:@total, DhanScalper::Support::Money.bd(95_000)) # 5000 loss
      fresh_balance_provider.instance_variable_set(:@available, DhanScalper::Support::Money.bd(95_000)) # Update available too

      # Mock current price to be slightly profitable to avoid stop loss triggers
      # but not so profitable that it offsets the balance loss
      allow(DhanScalper::TickCache).to receive(:ltp).and_return(101.0) # 1% profit

      # Manually trigger the daily loss cap check to test the functionality
      # This should now detect the 5000 loss and trigger position closure
      risk_mgr.send(:check_daily_loss_cap)

      # Verify exit orders were placed for all positions due to daily loss cap
      expect(broker_mock).to have_received(:place_order!).with(
        symbol: "TEST123",
        instrument_id: "TEST123",
        side: "SELL",
        quantity: 75,
        price: 101.0,
        order_type: "MARKET",
        idempotency_key: match(/risk_exit_TEST123_DAILY_LOSS_CAP_/),
      )

      expect(broker_mock).to have_received(:place_order!).with(
        symbol: "TEST456",
        instrument_id: "TEST456",
        side: "SELL",
        quantity: 50,
        price: 101.0,
        order_type: "MARKET",
        idempotency_key: match(/risk_exit_TEST456_DAILY_LOSS_CAP_/),
      )
    end

    it "does not close positions when loss is within cap" do
      # Create a position
      position_tracker.add_position(
        exchange_segment: "NSE_EQ",
        security_id: "TEST123",
        side: "LONG",
        quantity: 75,
        price: 100.0,
      )

      # Simulate a small loss within the cap
      balance_provider.instance_variable_set(:@total, DhanScalper::Support::Money.bd(99_500)) # 500 loss

      # Start risk manager
      risk_manager.start

      # Wait a bit for the risk loop to run
      sleep(0.1)

      # Verify no exit order was placed due to daily loss cap
      expect(broker).not_to have_received(:place_order!)

      risk_manager.stop
    end
  end

  describe "Cooldown" do
    it "enters cooldown after a loss" do
      # Create a fresh broker mock for this test
      broker_mock = double("Broker")
      allow(broker_mock).to receive(:place_order!).and_return({ order_status: "FILLED", order_id: "test_order_123" })

      # Create fresh position tracker and risk manager
      fresh_position_tracker = DhanScalper::Services::EnhancedPositionTracker.new
      fresh_equity_calculator = DhanScalper::Services::EquityCalculator.new(balance_provider: balance_provider, position_tracker: fresh_position_tracker)
      risk_mgr = described_class.new(config, fresh_position_tracker, broker_mock, balance_provider, fresh_equity_calculator)

      # Create a position
      fresh_position_tracker.add_position(
        exchange_segment: "NSE_EQ",
        security_id: "TEST123",
        side: "LONG",
        quantity: 75,
        price: 100.0,
      )

      # Mock a loss scenario (current price below entry - 18% loss to trigger stop loss)
      allow(DhanScalper::TickCache).to receive(:ltp).and_return(82.0)

      # Start risk manager
      risk_mgr.start

      # Wait a bit for the risk loop to run
      sleep(0.1)

      # Verify exit order was placed
      expect(broker_mock).to have_received(:place_order!)

      # Check that cooldown is active
      expect(risk_mgr.in_cooldown?).to be true

      risk_mgr.stop
    end

    it "exits cooldown after cooldown period" do
      # Create a fresh broker mock for this test
      broker_mock = double("Broker")
      allow(broker_mock).to receive(:place_order!).and_return({ order_status: "FILLED", order_id: "test_order_123" })

      # Create fresh position tracker and risk manager
      fresh_position_tracker = DhanScalper::Services::EnhancedPositionTracker.new
      fresh_equity_calculator = DhanScalper::Services::EquityCalculator.new(balance_provider: balance_provider, position_tracker: fresh_position_tracker)
      risk_mgr = described_class.new(config, fresh_position_tracker, broker_mock, balance_provider, fresh_equity_calculator)

      # Create a position
      fresh_position_tracker.add_position(
        exchange_segment: "NSE_EQ",
        security_id: "TEST123",
        side: "LONG",
        quantity: 75,
        price: 100.0,
      )

      # Mock a loss scenario (18% loss to trigger stop loss)
      allow(DhanScalper::TickCache).to receive(:ltp).and_return(82.0)

      # Start risk manager
      risk_mgr.start

      # Wait a bit for the risk loop to run
      sleep(0.1)

      # Verify cooldown is active
      expect(risk_mgr.in_cooldown?).to be true

      # Mock time passing beyond cooldown period
      risk_mgr.instance_variable_set(:@last_loss_time, Time.now - 4) # 4 seconds ago

      # Check cooldown status
      expect(risk_mgr.in_cooldown?).to be false

      risk_mgr.stop
    end

    it "skips position checks during cooldown" do
      # Create a position
      position_tracker.add_position(
        exchange_segment: "NSE_EQ",
        security_id: "TEST123",
        side: "LONG",
        quantity: 75,
        price: 100.0,
      )

      # Manually set cooldown
      risk_manager.instance_variable_set(:@last_loss_time, Time.now - 1)
      risk_manager.instance_variable_set(:@in_cooldown, true)

      # Start risk manager
      risk_manager.start

      # Wait a bit for the risk loop to run
      sleep(0.1)

      # Verify no exit order was placed during cooldown
      expect(broker).not_to have_received(:place_order!)

      risk_manager.stop
    end
  end

  describe "Take Profit and Stop Loss" do
    it "exits position on take profit" do
      # Create a position
      position_tracker.add_position(
        exchange_segment: "NSE_EQ",
        security_id: "TEST123",
        side: "LONG",
        quantity: 75,
        price: 100.0,
      )

      # Mock profitable price (35% profit)
      allow(DhanScalper::TickCache).to receive(:ltp).and_return(135.0)

      # Start risk manager
      risk_manager.start

      # Wait a bit for the risk loop to run
      sleep(0.1)

      # Verify exit order was placed
      expect(broker).to have_received(:place_order!).with(
        symbol: "TEST123",
        instrument_id: "TEST123",
        side: "SELL",
        quantity: 75,
        price: 135.0,
        order_type: "MARKET",
        idempotency_key: match(/risk_exit_TEST123_TP_/),
      )

      risk_manager.stop
    end

    it "exits position on stop loss" do
      # Create a position
      position_tracker.add_position(
        exchange_segment: "NSE_EQ",
        security_id: "TEST123",
        side: "LONG",
        quantity: 75,
        price: 100.0,
      )

      # Mock loss price (18% loss)
      allow(DhanScalper::TickCache).to receive(:ltp).and_return(82.0)

      # Start risk manager
      risk_manager.start

      # Wait a bit for the risk loop to run
      sleep(0.1)

      # Verify exit order was placed
      expect(broker).to have_received(:place_order!).with(
        symbol: "TEST123",
        instrument_id: "TEST123",
        side: "SELL",
        quantity: 75,
        price: 82.0,
        order_type: "MARKET",
        idempotency_key: match(/risk_exit_TEST123_SL_/),
      )

      risk_manager.stop
    end
  end

  describe "Idempotency Keys" do
    it "generates unique idempotency keys for each exit" do
      # Create a position
      position_tracker.add_position(
        exchange_segment: "NSE_EQ",
        security_id: "TEST123",
        side: "LONG",
        quantity: 75,
        price: 100.0,
      )

      # Mock profitable price
      allow(DhanScalper::TickCache).to receive(:ltp).and_return(135.0)

      # Start risk manager
      risk_manager.start

      # Wait a bit for the risk loop to run
      sleep(0.1)

      # Verify idempotency key format
      expect(broker).to have_received(:place_order!).with(
        hash_including(idempotency_key: match(/^risk_exit_TEST123_TP_\d+_[a-f0-9]{8}$/)),
      )

      risk_manager.stop
    end
  end

  describe "Configuration Validation" do
    it "handles disabled features" do
      disabled_config = config.dup
      disabled_config["global"]["enable_time_stop"] = false
      disabled_config["global"]["enable_daily_loss_cap"] = false
      disabled_config["global"]["enable_cooldown"] = false

      risk_manager = described_class.new(disabled_config, position_tracker, broker, balance_provider, equity_calculator)

      expect(risk_manager.instance_variable_get(:@enable_time_stop)).to be false
      expect(risk_manager.instance_variable_get(:@enable_daily_loss_cap)).to be false
      expect(risk_manager.instance_variable_get(:@enable_cooldown)).to be false
    end
  end

  describe "#reset_session" do
    it "resets session tracking" do
      risk_manager.start
      risk_manager.stop

      # Manually set some session state
      risk_manager.instance_variable_set(:@last_loss_time, Time.now)
      risk_manager.instance_variable_set(:@in_cooldown, true)

      # Reset session
      risk_manager.reset_session

      expect(risk_manager.instance_variable_get(:@last_loss_time)).to be_nil
      expect(risk_manager.instance_variable_get(:@in_cooldown)).to be false
      expect(risk_manager.instance_variable_get(:@session_start_equity)).to eq(equity_calculator.calculate_equity[:total_equity])
    end
  end
end
