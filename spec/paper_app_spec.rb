# frozen_string_literal: true

require "spec_helper"

RSpec.describe DhanScalper::PaperApp do
  let(:config) do
    {
      "global" => {
        "min_profit_target" => 1000,
        "max_day_loss" => 5000,
        "decision_interval" => 10,
        "log_level" => "INFO"
      },
      "paper" => {
        "starting_balance" => 200_000
      },
      "SYMBOLS" => {
        "NIFTY" => {
          "idx_sid" => "13",
          "seg_idx" => "IDX_I",
          "seg_opt" => "NSE_FNO",
          "strike_step" => 50,
          "lot_size" => 75,
          "qty_multiplier" => 1,
          "expiry_wday" => 4
        }
      }
    }
  end

  let(:paper_app) { described_class.new(config, quiet: true, enhanced: true) }

  before do
    # Mock DhanHQ
    allow(DhanHQ).to receive(:configure_with_env)
    allow(DhanHQ).to receive(:logger).and_return(double("Logger", level: 0, "level=": nil))
    allow(DhanHQ).to receive(:configure)
    allow(DhanScalper::Services::DhanHQConfig).to receive(:configure)
    
    # Mock DhanHQ::WS::Client
    mock_ws_client = double("WS::Client")
    allow(mock_ws_client).to receive(:start)
    allow(mock_ws_client).to receive(:on)
    allow(DhanHQ::WS::Client).to receive(:new).and_return(mock_ws_client)

    # Mock WebSocket manager
    mock_ws_manager = double("WebSocketManager")
    allow(mock_ws_manager).to receive(:connect)
    allow(mock_ws_manager).to receive(:connected?).and_return(true)
    allow(mock_ws_manager).to receive(:on_price_update)
    allow(mock_ws_manager).to receive(:subscribe_to_instrument)
    allow(mock_ws_manager).to receive(:unsubscribe_from_instrument)
    allow(paper_app).to receive(:instance_variable_get).and_call_original
    allow(paper_app).to receive(:instance_variable_get).with(:@websocket_manager).and_return(mock_ws_manager)

    # Mock position tracker
    mock_position_tracker = double("PaperPositionTracker")
    allow(mock_position_tracker).to receive(:setup_websocket_handlers)
    allow(mock_position_tracker).to receive(:get_total_pnl).and_return(0.0)
    allow(mock_position_tracker).to receive(:get_positions_summary).and_return({
                                                                                 total_positions: 0,
                                                                                 open_positions: 0,
                                                                                 closed_positions: 0,
                                                                                 total_pnl: 0.0,
                                                                                 winning_trades: 0,
                                                                                 losing_trades: 0
                                                                               })
    allow(paper_app).to receive(:instance_variable_get).with(:@position_tracker).and_return(mock_position_tracker)

    # Mock broker
    mock_broker = double("PaperBroker")
    allow(mock_broker).to receive(:place_order).and_return({
                                                             success: true,
                                                             order_id: "P-1234567890",
                                                             order: double("Order", quantity: 75, price: 150.0),
                                                             position: double("Position", security_id: "TEST123")
                                                           })
    allow(paper_app).to receive(:instance_variable_get).with(:@broker).and_return(mock_broker)

    # Mock CSV master
    mock_csv_master = double("CsvMaster")
    allow(mock_csv_master).to receive(:get_expiry_dates).and_return(["2024-12-26"])
    allow(mock_csv_master).to receive(:get_security_id).and_return("TEST123")
    allow(mock_csv_master).to receive(:get_lot_size).and_return(75)
    allow(paper_app).to receive(:instance_variable_get).with(:@csv_master).and_return(mock_csv_master)

    # Mock option picker
    mock_picker = double("OptionPicker")
    allow(mock_picker).to receive(:pick).and_return({
                                                      ce: { strike: 25_000, security_id: "CE123", premium: 150.0 },
                                                      pe: { strike: 25_000, security_id: "PE123", premium: 120.0 }
                                                    })
    allow(paper_app).to receive(:instance_variable_get).with(:@picker).and_return(mock_picker)

    # Mock trend analysis
    mock_trend = double("TrendEnhanced")
    allow(mock_trend).to receive(:decide).and_return(:bullish)
    allow(paper_app).to receive(:instance_variable_get).with(:@trend).and_return(mock_trend)
  end

  describe "#initialize" do
    it "initializes with correct configuration" do
      expect(paper_app.instance_variable_get(:@cfg)).to eq(config)
      expect(paper_app.instance_variable_get(:@quiet)).to be true
      expect(paper_app.instance_variable_get(:@enhanced)).to be true
    end

    it "sets up session data" do
      session_data = paper_app.instance_variable_get(:@session_data)
      expect(session_data[:total_trades]).to eq(0)
      expect(session_data[:successful_trades]).to eq(0)
      expect(session_data[:failed_trades]).to eq(0)
      expect(session_data[:symbols_traded]).to be_a(Set)
    end
  end

  describe "#start" do
    before do
      allow(paper_app).to receive(:initialize_components)
      allow(paper_app).to receive(:start_websocket_connection)
      allow(paper_app).to receive(:start_tracking_underlyings)
      allow(paper_app).to receive(:subscribe_to_atm_options_for_monitoring)
      allow(paper_app).to receive(:main_trading_loop)
      allow(paper_app).to receive(:cleanup_and_report)
    end

    it "initializes all components" do
      expect(paper_app).to receive(:initialize_components)
      paper_app.start
    end

    it "starts WebSocket connection" do
      expect(paper_app).to receive(:start_websocket_connection)
      paper_app.start
    end

    it "starts tracking underlyings" do
      expect(paper_app).to receive(:start_tracking_underlyings)
      paper_app.start
    end

    it "subscribes to ATM options for monitoring" do
      expect(paper_app).to receive(:subscribe_to_atm_options_for_monitoring)
      paper_app.start
    end

    it "runs main trading loop" do
      expect(paper_app).to receive(:main_trading_loop)
      paper_app.start
    end

    it "performs cleanup and reporting" do
      expect(paper_app).to receive(:cleanup_and_report)
      paper_app.start
    end
  end

  describe "#analyze_and_trade" do
    before do
      allow(paper_app).to receive(:get_holy_grail_signal).and_return(:bullish)
      allow(paper_app).to receive(:get_current_spot_price).and_return(25_000.0)
      allow(paper_app).to receive(:execute_trade)
    end

    it "analyzes signals for each symbol" do
      expect(paper_app).to receive(:get_holy_grail_signal).with("NIFTY")
      expect(paper_app).to receive(:get_current_spot_price).with("NIFTY")
      paper_app.send(:analyze_and_trade)
    end

    it "executes trades when signals are generated" do
      expect(paper_app).to receive(:execute_trade).with("NIFTY", :bullish, 25_000.0, config["SYMBOLS"]["NIFTY"])
      paper_app.send(:analyze_and_trade)
    end

    it "skips trading when no signal" do
      allow(paper_app).to receive(:get_holy_grail_signal).and_return(:none)
      expect(paper_app).not_to receive(:execute_trade)
      paper_app.send(:analyze_and_trade)
    end
  end

  describe "#execute_trade" do
    let(:symbol) { "NIFTY" }
    let(:direction) { :bullish }
    let(:spot_price) { 25_000.0 }
    let(:symbol_config) { config["SYMBOLS"]["NIFTY"] }

    before do
      allow(paper_app).to receive(:get_cached_picker).and_return(double("OptionPicker"))
      allow(paper_app).to receive(:get_cached_trend).and_return(double("TrendEnhanced"))
    end

    it "executes buy trade for bullish signal" do
      expect(paper_app).to receive(:execute_buy_trade).with(symbol, direction, spot_price, symbol_config)
      paper_app.send(:execute_trade, symbol, direction, spot_price, symbol_config)
    end

    it "executes sell trade for bearish signal" do
      expect(paper_app).to receive(:execute_sell_trade).with(symbol, :bearish, spot_price, symbol_config)
      paper_app.send(:execute_trade, symbol, :bearish, spot_price, symbol_config)
    end

    it "skips execution for none signal" do
      expect(paper_app).not_to receive(:execute_buy_trade)
      expect(paper_app).not_to receive(:execute_sell_trade)
      paper_app.send(:execute_trade, symbol, :none, spot_price, symbol_config)
    end
  end

  describe "#execute_buy_trade" do
    let(:symbol) { "NIFTY" }
    let(:direction) { :bullish }
    let(:spot_price) { 25_000.0 }
    let(:symbol_config) { config["SYMBOLS"]["NIFTY"] }

    before do
      mock_picker = double("OptionPicker")
      allow(mock_picker).to receive(:pick).and_return({
                                                        ce: { strike: 25_000, security_id: "CE123", premium: 150.0 },
                                                        pe: { strike: 25_000, security_id: "PE123", premium: 120.0 }
                                                      })
      allow(paper_app).to receive(:get_cached_picker).and_return(mock_picker)

      mock_trend = double("TrendEnhanced")
      allow(mock_trend).to receive(:decide).and_return(:bullish)
      allow(paper_app).to receive(:get_cached_trend).and_return(mock_trend)
    end

    it "selects appropriate option based on trend" do
      expect(paper_app).to receive(:get_cached_trend).with(symbol, symbol_config)
      paper_app.send(:execute_buy_trade, symbol, direction, spot_price, symbol_config)
    end

    it "places order through broker" do
      mock_broker = paper_app.instance_variable_get(:@broker)
      expect(mock_broker).to receive(:place_order).with(
        symbol: symbol,
        instrument_id: "CE123",
        side: "BUY",
        quantity: 75,
        price: 150.0,
        order_type: "MARKET"
      )
      paper_app.send(:execute_buy_trade, symbol, direction, spot_price, symbol_config)
    end

    it "updates session data on successful trade" do
      allow(paper_app).to receive(:puts) # Suppress output
      paper_app.send(:execute_buy_trade, symbol, direction, spot_price, symbol_config)

      session_data = paper_app.instance_variable_get(:@session_data)
      expect(session_data[:total_trades]).to eq(1)
      expect(session_data[:successful_trades]).to eq(1)
      expect(session_data[:symbols_traded]).to include(symbol)
    end
  end

  describe "#check_risk_limits" do
    it "checks daily loss limit" do
      mock_position_tracker = paper_app.instance_variable_get(:@position_tracker)
      allow(mock_position_tracker).to receive(:get_total_pnl).and_return(-6000.0)

      expect(paper_app).to receive(:puts).with(/Daily loss limit breached/)
      paper_app.send(:check_risk_limits)
    end

    it "continues trading when within limits" do
      mock_position_tracker = paper_app.instance_variable_get(:@position_tracker)
      allow(mock_position_tracker).to receive(:get_total_pnl).and_return(-1000.0)

      expect(paper_app).not_to receive(:puts)
      paper_app.send(:check_risk_limits)
    end
  end

  describe "#show_position_summary" do
    it "displays position summary" do
      mock_position_tracker = paper_app.instance_variable_get(:@position_tracker)
      allow(mock_position_tracker).to receive(:get_positions_summary).and_return({
                                                                                   total_positions: 2,
                                                                                   open_positions: 1,
                                                                                   closed_positions: 1,
                                                                                   total_pnl: 500.0,
                                                                                   winning_trades: 1,
                                                                                   losing_trades: 0
                                                                                 })

      expect(paper_app).to receive(:puts).with(/Position Summary/)
      expect(paper_app).to receive(:puts).with(/Total Positions: 2/)
      expect(paper_app).to receive(:puts).with(/Open Positions: 1/)
      expect(paper_app).to receive(:puts).with(/Total P&L: ₹500.0/)
      paper_app.send(:show_position_summary)
    end
  end

  describe "#generate_session_report" do
    it "generates comprehensive session report" do
      mock_position_tracker = paper_app.instance_variable_get(:@position_tracker)
      allow(mock_position_tracker).to receive(:get_positions_summary).and_return({
                                                                                   total_positions: 1,
                                                                                   open_positions: 0,
                                                                                   closed_positions: 1,
                                                                                   total_pnl: 750.0,
                                                                                   winning_trades: 1,
                                                                                   losing_trades: 0
                                                                                 })

      mock_reporter = double("SessionReporter")
      allow(mock_reporter).to receive(:generate_session_report)
      allow(paper_app).to receive(:instance_variable_get).with(:@reporter).and_return(mock_reporter)

      expect(mock_reporter).to receive(:generate_session_report)
      paper_app.send(:generate_session_report)
    end
  end

  describe "error handling" do
    it "handles WebSocket connection failures gracefully" do
      allow(paper_app).to receive(:start_websocket_connection).and_raise(StandardError, "Connection failed")
      expect { paper_app.start }.to raise_error(StandardError, "Connection failed")
    end

    it "handles broker errors gracefully" do
      mock_broker = paper_app.instance_variable_get(:@broker)
      allow(mock_broker).to receive(:place_order).and_raise(StandardError, "Order failed")

      expect do
        paper_app.send(:execute_buy_trade, "NIFTY", :bullish, 25_000.0,
                       config["SYMBOLS"]["NIFTY"])
      end.to raise_error(StandardError, "Order failed")
    end

    it "handles CSV master errors gracefully" do
      mock_csv_master = paper_app.instance_variable_get(:@csv_master)
      allow(mock_csv_master).to receive(:get_expiry_dates).and_raise(StandardError, "CSV error")

      expect do
        paper_app.send(:execute_buy_trade, "NIFTY", :bullish, 25_000.0,
                       config["SYMBOLS"]["NIFTY"])
      end.to raise_error(StandardError, "CSV error")
    end
  end

  describe "timeout handling" do
    it "respects timeout when specified" do
      paper_app_with_timeout = described_class.new(config, quiet: true, enhanced: true, timeout_minutes: 1)
      allow(paper_app_with_timeout).to receive(:initialize_components)
      allow(paper_app_with_timeout).to receive(:start_websocket_connection)
      allow(paper_app_with_timeout).to receive(:start_tracking_underlyings)
      allow(paper_app_with_timeout).to receive(:subscribe_to_atm_options_for_monitoring)
      allow(paper_app_with_timeout).to receive(:main_trading_loop)
      allow(paper_app_with_timeout).to receive(:cleanup_and_report)

      expect(paper_app_with_timeout.instance_variable_get(:@timeout_minutes)).to eq(1)
      paper_app_with_timeout.start
    end
  end
end
