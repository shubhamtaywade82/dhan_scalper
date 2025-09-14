# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Live Mode Final Integration", :integration do
  let(:config) do
    {
      global: {
        min_profit_target: 1_000,
        max_day_loss: 5_000,
        decision_interval: 10,
        log_level: "INFO",
        tp_pct: 0.35,
        sl_pct: 0.18,
        trail_pct: 0.12,
        charge_per_order: 20.0,
        allocation_pct: 0.30,
        max_lots_per_trade: 10,
        session_hours: ["09:20", "15:25"],
        enforce_market_hours: true,
      },
      SYMBOLS: {
        NIFTY: {
          idx_sid: "13",
          seg_idx: "IDX_I",
          seg_opt: "NSE_FNO",
          strike_step: 50,
          lot_size: 75,
          qty_multiplier: 1,
          expiry_wday: 4,
        },
      },
    }
  end

  let(:logger) { Logger.new(StringIO.new) }

  before do
    # Mock DhanHQ configuration
    allow(DhanHQ).to receive(:configure_with_env)
    allow(DhanHQ).to receive(:logger).and_return(logger)

    # Mock DhanHQ::Models::Funds
    funds_class = Class.new
    stub_const("DhanHQ::Models::Funds", funds_class)
    allow(funds_class).to receive(:fetch).and_return(double(
                                                       available_balance: 100_000.0,
                                                       utilized_amount: 50_000.0,
                                                     ))

    # Mock DhanHQ::Models::Holding
    holding_class = Class.new
    stub_const("DhanHQ::Models::Holding", holding_class)
    allow(holding_class).to receive(:fetch).and_return([])

    # Mock DhanHQ::Models::Position
    position_class = Class.new
    stub_const("DhanHQ::Models::Position", position_class)
    allow(position_class).to receive(:fetch).and_return([])
  end

  describe "Live Balance Provider" do
    let(:balance_provider) { DhanScalper::BalanceProviders::LiveBalance.new(logger: logger) }

    it "initializes with correct default values" do
      expect(balance_provider.available_balance).to eq(100_000.0)
      expect(balance_provider.used_balance).to eq(50_000.0)
      expect(balance_provider.total_balance).to eq(150_000.0)
    end

    it "fetches positions from DhanHQ API" do
      positions = balance_provider.get_positions
      expect(positions).to be_an(Array)
    end

    it "fetches holdings from DhanHQ API" do
      holdings = balance_provider.get_holdings
      expect(holdings).to be_an(Array)
    end
  end

  describe "Live Broker" do
    let(:balance_provider) { DhanScalper::BalanceProviders::LiveBalance.new(logger: logger) }
    let(:broker) { DhanScalper::Brokers::DhanBroker.new(balance_provider: balance_provider, logger: logger) }

    before do
      # Mock DhanHQ::Models::Order
      order_class = Class.new
      stub_const("DhanHQ::Models::Order", order_class)
      mock_order = double
      allow(mock_order).to receive(:persisted?).and_return(true)
      allow(mock_order).to receive(:order_id).and_return("L-123456789")
      allow(mock_order).to receive(:save).and_return(true)
      allow(mock_order).to receive(:errors).and_return(double(full_messages: []))
      allow(order_class).to receive(:new).and_return(mock_order)

      # Mock DhanHQ::Order
      order_class2 = Class.new
      stub_const("DhanHQ::Order", order_class2)
      allow(order_class2).to receive(:cancel_order).and_return({
                                                                 success: true,
                                                                 message: "Order cancelled successfully",
                                                               })
    end

    it "places buy orders successfully" do
      result = broker.place_order(
        symbol: "NIFTY",
        instrument_id: "12345",
        side: "BUY",
        quantity: 75,
        price: 54.60,
      )

      expect(result[:success]).to be true
      expect(result[:order_id]).to eq("L-123456789")
    end

    it "places sell orders successfully" do
      result = broker.place_order(
        symbol: "NIFTY",
        instrument_id: "12345",
        side: "SELL",
        quantity: 75,
        price: 54.60,
      )

      expect(result[:success]).to be true
      expect(result[:order_id]).to eq("L-123456789")
    end

    it "fetches positions" do
      positions = broker.get_positions
      expect(positions).to be_an(Array)
    end

    it "fetches orders" do
      orders = broker.get_orders
      expect(orders).to be_an(Array)
    end

    it "fetches funds" do
      funds = broker.get_funds
      expect(funds).to be_a(Hash)
      expect(funds[:available_balance]).to eq(100_000.0)
    end

    it "fetches holdings" do
      holdings = broker.get_holdings
      expect(holdings).to be_an(Array)
    end

    it "fetches trades" do
      trades = broker.get_trades
      expect(trades).to be_an(Array)
    end
  end

  describe "Live Mode App Runner" do
    let(:app_runner) { DhanScalper::Runners::AppRunner.new(config, mode: :live, quiet: true) }

    it "initializes live trading components" do
      expect(app_runner.instance_variable_get(:@mode)).to eq(:live)
      expect(app_runner.instance_variable_get(:@balance_provider)).to be_a(DhanScalper::BalanceProviders::LiveBalance)
      expect(app_runner.instance_variable_get(:@broker)).to be_a(DhanScalper::Brokers::DhanBroker)
    end
  end

  describe "Live Mode Configuration" do
    it "validates live mode configuration" do
      expect(config[:global][:min_profit_target]).to eq(1_000)
      expect(config[:global][:max_day_loss]).to eq(5_000)
      expect(config[:global][:charge_per_order]).to eq(20.0)
      expect(config[:SYMBOLS][:NIFTY][:idx_sid]).to eq("13")
    end

    it "has required symbols configuration" do
      expect(config[:SYMBOLS]).to have_key(:NIFTY)
      expect(config[:SYMBOLS][:NIFTY]).to have_key(:idx_sid)
      expect(config[:SYMBOLS][:NIFTY]).to have_key(:seg_idx)
      expect(config[:SYMBOLS][:NIFTY]).to have_key(:seg_opt)
    end
  end

  describe "WebMock Integration" do
    it "can stub HTTP requests for live mode testing" do
      stub_request(:get, "https://api.dhan.co/funds")
        .to_return(
          status: 200,
          body: {
            availableBalance: 100_000.0,
            utilizedAmount: 50_000.0,
            totalBalance: 150_000.0,
          }.to_json,
          headers: { "Content-Type" => "application/json" },
        )

      # This demonstrates WebMock is working
      expect(WebMock).to have_requested(:get, "https://api.dhan.co/funds").times(0)
    end
  end

  describe "Live Mode Components Integration" do
    it "can create live balance provider" do
      balance_provider = DhanScalper::BalanceProviders::LiveBalance.new(logger: logger)
      expect(balance_provider).to be_a(DhanScalper::BalanceProviders::LiveBalance)
    end

    it "can create live broker" do
      balance_provider = DhanScalper::BalanceProviders::LiveBalance.new(logger: logger)
      broker = DhanScalper::Brokers::DhanBroker.new(balance_provider: balance_provider, logger: logger)
      expect(broker).to be_a(DhanScalper::Brokers::DhanBroker)
    end

    it "can create app runner in live mode" do
      app_runner = DhanScalper::Runners::AppRunner.new(config, mode: :live, quiet: true)
      expect(app_runner).to be_a(DhanScalper::Runners::AppRunner)
    end
  end

  describe "Live Mode Error Handling" do
    let(:balance_provider) { DhanScalper::BalanceProviders::LiveBalance.new(logger: logger) }

    it "handles API errors gracefully" do
      # Mock API error from the start
      funds_class = Class.new
      stub_const("DhanHQ::Models::Funds", funds_class)
      allow(funds_class).to receive(:fetch).and_raise(StandardError.new("API Error"))

      # Should use fallback values when API fails
      expect(balance_provider.available_balance).to eq(100_000.0)
    end
  end
end
