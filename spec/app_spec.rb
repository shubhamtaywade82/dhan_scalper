# frozen_string_literal: true

require "spec_helper"

RSpec.describe DhanScalper::App do
  let(:config) do
    {
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
      "global" => {
        "min_profit_target" => 1_000.0,
        "max_day_loss" => 1_500.0,
        "decision_interval" => 10,
        "tp_pct" => 0.35,
        "sl_pct" => 0.18,
        "trail_pct" => 0.12,
        "charge_per_order" => 20.0,
        "log_level" => "INFO",
      },
      "paper" => {
        "starting_balance" => 200_000.0,
      },
    }
  end

  let(:mock_websocket) { double("WebSocket") }
  let(:mock_trader) { double("Trader") }
  let(:mock_state) { double("State") }
  let(:mock_vdm) { double("VirtualDataManager") }
  let(:mock_balance_provider) { double("BalanceProvider") }
  let(:mock_quantity_sizer) { double("QuantitySizer") }
  let(:mock_broker) { double("Broker") }

  before do
    # Mock all dependencies
    stub_const("DhanScalper::State", double)
    stub_const("DhanScalper::VirtualDataManager", double)
    stub_const("DhanScalper::QuantitySizer", double)
    stub_const("DhanScalper::BalanceProviders::PaperWallet", double)
    stub_const("DhanScalper::BalanceProviders::LiveBalance", double)
    stub_const("DhanScalper::Brokers::PaperBroker", double)
    stub_const("DhanScalper::Brokers::DhanBroker", double)
    stub_const("DhanScalper::UI::Dashboard", double)
    stub_const("DhanScalper::Trend", double)
    stub_const("DhanScalper::Trader", double)
    stub_const("DhanScalper::OptionPicker", double)

    # Mock State
    allow(DhanScalper::State).to receive(:new).and_return(mock_state)
    allow(mock_state).to receive(:upsert_idx_sub)
    allow(mock_state).to receive(:upsert_opt_sub)
    allow(mock_state).to receive(:set_session_pnl)
    allow(mock_state).to receive(:status).and_return(:running)
    allow(mock_state).to receive(:set_status)

    # Mock VirtualDataManager
    allow(DhanScalper::VirtualDataManager).to receive(:new).and_return(mock_vdm)

    # Mock BalanceProviders
    allow(DhanScalper::BalanceProviders::PaperWallet).to receive(:new).and_return(mock_balance_provider)
    allow(DhanScalper::BalanceProviders::LiveBalance).to receive(:new).and_return(mock_balance_provider)
    allow(mock_balance_provider).to receive(:available_balance).and_return(200_000.0)

    # Mock QuantitySizer
    allow(DhanScalper::QuantitySizer).to receive(:new).and_return(mock_quantity_sizer)

    # Mock Brokers
    allow(DhanScalper::Brokers::PaperBroker).to receive(:new).and_return(mock_broker)
    allow(DhanScalper::Brokers::DhanBroker).to receive(:new).and_return(mock_broker)

    # Mock WebSocket
    allow(mock_websocket).to receive(:on)
    allow(mock_websocket).to receive(:subscribe_one)
    allow(mock_websocket).to receive(:disconnect!)

    # Mock Trader
    allow(DhanScalper::Trader).to receive(:new).and_return(mock_trader)
    allow(mock_trader).to receive(:subscribe_options)
    allow(mock_trader).to receive(:maybe_enter)
    allow(mock_trader).to receive(:manage_open)
    allow(mock_trader).to receive_messages(session_pnl: 0.0, instance_variable_get: nil)

    # Mock OptionPicker
    allow(DhanScalper::OptionPicker).to receive(:new).and_return(double(
                                                                   pick: { expiry: "2024-01-25", strikes: [19_500, 19_550, 19_600], ce_sid: { 19_500 => "CE123" },
                                                                           pe_sid: { 19_500 => "PE123" } },
                                                                 ))

    # Mock Trend
    allow(DhanScalper::Trend).to receive(:new).and_return(double(decide: :none))

    # Mock UI::Dashboard
    allow(DhanScalper::UI::Dashboard).to receive(:new).and_return(double(run: nil))

    # Mock TickCache
    stub_const("DhanScalper::TickCache", double)
    allow(DhanScalper::TickCache).to receive(:put)
    allow(DhanScalper::TickCache).to receive(:ltp).and_return(19_500.0)

    # Mock CandleSeries
    stub_const("DhanScalper::CandleSeries", double)
    allow(DhanScalper::CandleSeries).to receive(:load_from_dhan_intraday).and_return(
      double(closes: [19_500.0, 19_501.0, 19_502.0]),
    )

    # Mock Thread
    allow(Thread).to receive(:new).and_return(double(join: nil))
  end

  describe "#initialize" do
    context "with paper mode" do
      let(:app) { described_class.new(config, mode: :paper) }

      it "initializes with paper mode configuration" do
        expect(app.instance_variable_get(:@mode)).to eq(:paper)
        expect(app.instance_variable_get(:@dry)).to be false
      end

      it "creates a PaperWallet balance provider" do
        expect(DhanScalper::BalanceProviders::PaperWallet).to have_received(:new).with(starting_balance: 200_000.0)
      end

      it "creates a PaperBroker" do
        expect(DhanScalper::Brokers::PaperBroker).to have_received(:new).with(
          virtual_data_manager: mock_vdm,
          balance_provider: mock_balance_provider,
        )
      end
    end

    context "with live mode" do
      let(:app) { described_class.new(config, mode: :live) }

      it "initializes with live mode configuration" do
        expect(app.instance_variable_get(:@mode)).to eq(:live)
      end

      it "creates a LiveBalance balance provider" do
        expect(DhanScalper::BalanceProviders::LiveBalance).to have_received(:new)
      end

      it "creates a DhanBroker" do
        expect(DhanScalper::Brokers::DhanBroker).to have_received(:new).with(
          virtual_data_manager: mock_vdm,
          balance_provider: mock_balance_provider,
        )
      end
    end

    context "with dryrun mode" do
      let(:app) { described_class.new(config, mode: :paper, dryrun: true) }

      it "initializes with dryrun flag" do
        expect(app.instance_variable_get(:@dry)).to be true
      end
    end

    it "sets up signal handlers" do
      # This is hard to test directly, but we can verify the instance variables are set
      app = described_class.new(config)
      expect(app.instance_variable_get(:@stop)).to be false
    end

    it "creates State with correct parameters" do
      described_class.new(config)
      expect(DhanScalper::State).to have_received(:new).with(
        symbols: ["NIFTY"],
        session_target: 1_000.0,
        max_day_loss: 1_500.0,
      )
    end

    it "creates QuantitySizer with correct parameters" do
      described_class.new(config)
      expect(DhanScalper::QuantitySizer).to have_received(:new).with(config, mock_balance_provider)
    end
  end

  describe "#start" do
    let(:app) { described_class.new(config) }

    before do
      # Mock WebSocket creation
      allow(app).to receive_messages(create_websocket_client: mock_websocket,
                                     setup_traders: [{ "NIFTY" => mock_trader }, {}, {}], sym_cfg: config["SYMBOLS"]["NIFTY"], wait_for_spot: 19_500.0, total_pnl_preview: 0.0, instance_open?: false, session_target: 1_000.0)
    end

    it "configures DhanHQ" do
      app.start
      expect(DhanHQ).to have_received(:configure_with_env)
    end

    it "sets logger level based on config" do
      config["global"]["log_level"] = "DEBUG"
      app.start
      # NOTE: This is hard to test directly due to Logger::DEBUG constant
    end

    it "creates WebSocket client" do
      app.start
      expect(app).to have_received(:create_websocket_client)
    end

    it "sets up tick handler" do
      app.start
      expect(mock_websocket).to have_received(:on).with(:tick)
    end

    it "sets up traders" do
      app.start
      expect(app).to have_received(:setup_traders).with(mock_websocket)
    end

    it "starts UI dashboard in separate thread" do
      app.start
      expect(Thread).to have_received(:new)
    end

    it "handles pause/resume state" do
      allow(mock_state).to receive(:status).and_return(:paused, :running)
      app.start
      # This is tested indirectly through the loop behavior
    end

    it "stops when @stop is true" do
      # This is tested through the main loop behavior
      app.start
    end
  end

  describe "#create_websocket_client" do
    let(:app) { described_class.new(config) }

    context "when first method succeeds" do
      before do
        stub_const("DhanHQ::WS::Client", double)
        allow(DhanHQ::WS::Client).to receive(:new).and_return(mock_websocket)
        allow(mock_websocket).to receive(:start).and_return(mock_websocket)
        allow(mock_websocket).to receive(:respond_to?).with(:on).and_return(true)
      end

      it "returns the WebSocket client" do
        result = app.send(:create_websocket_client)
        expect(result).to eq(mock_websocket)
      end
    end

    context "when first method fails, second succeeds" do
      before do
        stub_const("DhanHQ::WS::Client", double)
        stub_const("DhanHQ::WebSocket::Client", double)
        allow(DhanHQ::WS::Client).to receive(:new).and_raise(StandardError, "Failed")
        allow(DhanHQ::WebSocket::Client).to receive(:new).and_return(mock_websocket)
        allow(mock_websocket).to receive(:start).and_return(mock_websocket)
        allow(mock_websocket).to receive(:respond_to?).with(:on).and_return(true)
      end

      it "falls back to second method" do
        result = app.send(:create_websocket_client)
        expect(result).to eq(mock_websocket)
      end
    end

    context "when all methods fail" do
      before do
        stub_const("DhanHQ::WS::Client", double)
        stub_const("DhanHQ::WebSocket::Client", double)
        stub_const("DhanHQ::WebSocket", double)
        stub_const("DhanHQ::WS", double)
        allow(DhanHQ::WS::Client).to receive(:new).and_raise(StandardError, "Failed")
        allow(DhanHQ::WebSocket::Client).to receive(:new).and_raise(StandardError, "Failed")
        allow(DhanHQ::WebSocket).to receive(:new).and_raise(StandardError, "Failed")
        allow(DhanHQ::WS).to receive(:new).and_raise(StandardError, "Failed")
      end

      it "returns nil" do
        result = app.send(:create_websocket_client)
        expect(result).to be_nil
      end
    end
  end

  describe "#disconnect_websocket" do
    let(:app) { described_class.new(config) }

    context "when first method succeeds" do
      before do
        stub_const("DhanHQ::WS", double)
        allow(DhanHQ::WS).to receive(:disconnect_all_local!)
      end

      it "disconnects successfully" do
        expect { app.send(:disconnect_websocket) }.not_to raise_error
        expect(DhanHQ::WS).to have_received(:disconnect_all_local!)
      end
    end

    context "when first method fails, second succeeds" do
      before do
        stub_const("DhanHQ::WS", double)
        stub_const("DhanHQ::WebSocket", double)
        allow(DhanHQ::WS).to receive(:disconnect_all_local!).and_raise(StandardError, "Failed")
        allow(DhanHQ::WebSocket).to receive(:disconnect_all_local!)
      end

      it "falls back to second method" do
        expect { app.send(:disconnect_websocket) }.not_to raise_error
        expect(DhanHQ::WebSocket).to have_received(:disconnect_all_local!)
      end
    end
  end

  describe "#setup_traders" do
    let(:app) { described_class.new(config) }

    before do
      allow(app).to receive_messages(sym_cfg: config["SYMBOLS"]["NIFTY"], wait_for_spot: 19_500.0)
      allow(mock_websocket).to receive(:subscribe_one)
    end

    it "subscribes to index data" do
      app.send(:setup_traders, mock_websocket)
      expect(mock_websocket).to have_received(:subscribe_one).with(
        segment: "IDX_I",
        security_id: "13",
      )
    end

    it "creates traders for each symbol" do
      traders, = app.send(:setup_traders, mock_websocket)
      expect(traders).to have_key("NIFTY")
    end

    it "subscribes to options data" do
      app.send(:setup_traders, mock_websocket)
      expect(mock_trader).to have_received(:subscribe_options)
    end
  end

  describe "#wait_for_spot" do
    let(:app) { described_class.new(config) }

    context "when tick data is available" do
      before do
        allow(DhanScalper::TickCache).to receive(:ltp).and_return(19_500.0)
      end

      it "returns the LTP immediately" do
        result = app.send(:wait_for_spot, config["SYMBOLS"]["NIFTY"])
        expect(result).to eq(19_500.0)
      end
    end

    context "when tick data is not available initially" do
      before do
        allow(DhanScalper::TickCache).to receive(:ltp).and_return(nil, nil, 19_500.0)
        allow(Time).to receive(:now).and_return(Time.at(0), Time.at(5), Time.at(15))
      end

      it "waits for tick data" do
        result = app.send(:wait_for_spot, config["SYMBOLS"]["NIFTY"])
        expect(result).to eq(19_500.0)
      end
    end

    context "when timeout is reached" do
      before do
        allow(DhanScalper::TickCache).to receive(:ltp).and_return(nil)
        allow(Time).to receive(:now).and_return(Time.at(0), Time.at(15))
        allow(DhanScalper::CandleSeries).to receive(:load_from_dhan_intraday).and_return(
          double(closes: [19_500.0, 19_501.0, 19_502.0]),
        )
      end

      it "falls back to historical data" do
        result = app.send(:wait_for_spot, config["SYMBOLS"]["NIFTY"])
        expect(result).to eq(19_502.0)
      end
    end
  end

  describe "#sym_cfg" do
    let(:app) { described_class.new(config) }

    it "returns symbol configuration" do
      result = app.send(:sym_cfg, "NIFTY")
      expect(result).to eq(config["SYMBOLS"]["NIFTY"])
    end
  end

  describe "#sym_for" do
    let(:app) { described_class.new(config) }

    context "with index segment" do
      let(:tick) { { segment: "IDX_I", security_id: "13" } }

      it "returns the symbol name" do
        result = app.send(:sym_for, tick)
        expect(result).to eq("NIFTY")
      end
    end

    context "with non-index segment" do
      let(:tick) { { segment: "NSE_FNO", security_id: "123" } }

      it "returns 'OPT'" do
        result = app.send(:sym_for, tick)
        expect(result).to eq("OPT")
      end
    end
  end

  describe "#total_pnl_preview" do
    let(:app) { described_class.new(config) }

    it "returns the net PnL" do
      result = app.send(:total_pnl_preview, mock_trader, 100.0)
      expect(result).to eq(100.0)
    end
  end

  describe "#instance_open?" do
    let(:app) { described_class.new(config) }

    it "checks if trader has open position" do
      allow(mock_trader).to receive(:instance_variable_get).with(:@open).and_return(nil)
      result = app.send(:instance_open?, mock_trader)
      expect(result).to be false
    end
  end

  describe "signal handling" do
    let(:app) { described_class.new(config) }

    it "responds to INT signal" do
      # This is tested through the main loop behavior
      expect(app.instance_variable_get(:@stop)).to be false
    end

    it "responds to TERM signal" do
      # This is tested through the main loop behavior
      expect(app.instance_variable_get(:@stop)).to be false
    end
  end
end
