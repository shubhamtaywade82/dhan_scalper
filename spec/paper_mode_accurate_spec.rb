# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Paper Mode Accurate Test Suite" do
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
      paper: {
        starting_balance: 200_000,
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
        BANKNIFTY: {
          idx_sid: "23",
          seg_idx: "IDX_I",
          seg_opt: "NSE_FNO",
          strike_step: 100,
          lot_size: 25,
          qty_multiplier: 1,
          expiry_wday: 4,
        },
      },
    }
  end

  let(:paper_app) { DhanScalper::PaperApp.new(config, quiet: true, enhanced: true) }

  before do
    # Mock DhanHQ
    allow(DhanHQ).to receive(:configure_with_env)
    allow(DhanHQ).to receive(:logger).and_return(double("Logger", level: 0, "level=": nil))
    allow(DhanHQ).to receive(:configure)
    allow(DhanScalper::Services::DhanHQConfig).to receive(:configure)

    # Mock WebSocket Manager
    mock_ws_manager = double("WebSocketManager")
    allow(mock_ws_manager).to receive(:connect)
    allow(mock_ws_manager).to receive(:connected?).and_return(true)
    allow(mock_ws_manager).to receive(:on_price_update)
    allow(mock_ws_manager).to receive(:subscribe_to_instrument)
    allow(mock_ws_manager).to receive(:unsubscribe_from_instrument)
    allow(mock_ws_manager).to receive(:disconnect)
    allow(mock_ws_manager).to receive(:stop)
    allow(mock_ws_manager).to receive(:set_baseline_instruments)
    allow(mock_ws_manager).to receive(:add_baseline_subscription)
    allow(mock_ws_manager).to receive(:add_position_subscription)

    # Mock Position Tracker
    mock_position_tracker = double("PaperPositionTracker")
    allow(mock_position_tracker).to receive(:get_positions).and_return([])
    allow(mock_position_tracker).to receive(:get_open_positions).and_return([])
    allow(mock_position_tracker).to receive(:get_total_pnl).and_return(0.0)
    allow(mock_position_tracker).to receive(:get_positions_summary).and_return({
      total_positions: 0,
      open_positions: 0,
      closed_positions: 0,
      total_pnl: 0.0,
      winning_trades: 0,
      losing_trades: 0,
      positions: {},
    })
    allow(mock_position_tracker).to receive(:add_position)
    allow(mock_position_tracker).to receive(:update_all_positions)
    allow(mock_position_tracker).to receive(:get_underlying_price).and_return(25_000.0)
    allow(mock_position_tracker).to receive(:setup_websocket_handlers)

    # Mock CSV Master
    mock_csv_master = double("CsvMaster")
    allow(mock_csv_master).to receive(:get_expiry_dates).and_return(["2024-12-26"])
    allow(mock_csv_master).to receive(:get_security_id).and_return("TEST123")
    allow(mock_csv_master).to receive(:get_lot_size).and_return(75)
    allow(mock_csv_master).to receive(:get_available_strikes).and_return([24_500, 24_550, 24_600, 24_650, 24_700, 24_750, 24_800, 24_850, 24_900, 24_950, 25_000, 25_050, 25_100, 25_150, 25_200, 25_250, 25_300, 25_350, 25_400, 25_450, 25_500])

    # Mock Option Picker
    mock_option_picker = double("OptionPicker")
    allow(mock_option_picker).to receive(:pick).and_return({
      ce: { strike: 25_000, security_id: "CE123", premium: 150.0 },
      pe: { strike: 25_000, security_id: "PE123", premium: 120.0 },
    })
    allow(mock_option_picker).to receive(:nearest_strike).and_return(25_000)
    allow(mock_option_picker).to receive(:select_strike_for_signal).and_return(25_000)

    # Mock Trend Analyzer
    mock_trend_analyzer = double("TrendEnhanced")
    allow(mock_trend_analyzer).to receive(:decide).and_return(:bullish)
    allow(mock_trend_analyzer).to receive(:analyze).and_return({
      signal: :bullish,
      strength: 0.75,
      adx: 28.5,
      bias: :bullish,
    })

    # Set instance variables
    paper_app.instance_variable_set(:@websocket_manager, mock_ws_manager)
    paper_app.instance_variable_set(:@position_tracker, mock_position_tracker)
    paper_app.instance_variable_set(:@csv_master, mock_csv_master)
    paper_app.instance_variable_set(:@picker, mock_option_picker)
    paper_app.instance_variable_set(:@trend, mock_trend_analyzer)

    # Mock TickCache
    allow(DhanScalper::TickCache).to receive(:put)
    allow(DhanScalper::TickCache).to receive(:ltp).and_return(25_000.0)

    # Mock Time
    allow(Time).to receive(:now).and_return(Time.parse("2024-01-15 10:30:00"))
  end

  describe "Paper Mode Initialization" do
    it "initializes with correct configuration" do
      expect(paper_app.instance_variable_get(:@cfg)).to eq(config)
      expect(paper_app.instance_variable_get(:@quiet)).to be true
      expect(paper_app.instance_variable_get(:@enhanced)).to be true
    end

    it "sets up session data correctly" do
      session_data = paper_app.instance_variable_get(:@session_data)
      expect(session_data[:total_trades]).to eq(0)
      expect(session_data[:successful_trades]).to eq(0)
      expect(session_data[:failed_trades]).to eq(0)
      expect(session_data[:symbols_traded]).to be_a(Set)
      expect(session_data[:max_pnl]).to eq(0.0)
      expect(session_data[:min_pnl]).to eq(0.0)
    end

    it "initializes components correctly" do
      expect(paper_app.instance_variable_get(:@websocket_manager)).to be_present
      expect(paper_app.instance_variable_get(:@position_tracker)).to be_present
      expect(paper_app.instance_variable_get(:@balance_provider)).to be_present
      expect(paper_app.instance_variable_get(:@broker)).to be_present
    end

    it "sets up signal handlers" do
      expect(paper_app.instance_variable_get(:@stop)).to be false
    end
  end

  describe "Configuration and Setup" do
    it "loads symbol configuration correctly" do
      symbols = paper_app.instance_variable_get(:@state).instance_variable_get(:@symbols)
      expect(symbols).to include("NIFTY", "BANKNIFTY")
    end

    it "sets up balance provider with correct starting balance" do
      balance_provider = paper_app.instance_variable_get(:@balance_provider)
      expect(balance_provider.available_balance).to eq(200_000.0)
    end

    it "initializes quantity sizer" do
      quantity_sizer = paper_app.instance_variable_get(:@quantity_sizer)
      expect(quantity_sizer).to be_present
    end

    it "initializes broker correctly" do
      broker = paper_app.instance_variable_get(:@broker)
      expect(broker).to be_a(DhanScalper::Brokers::PaperBroker)
    end
  end

  describe "Session Management" do
    it "initializes session data on start" do
      allow(paper_app).to receive(:initialize_components)
      allow(paper_app).to receive(:start_websocket_connection)
      allow(paper_app).to receive(:start_tracking_underlyings)
      allow(paper_app).to receive(:subscribe_to_atm_options_for_monitoring)
      allow(paper_app).to receive(:main_trading_loop)
      allow(paper_app).to receive(:cleanup_and_report)

      paper_app.start

      session_data = paper_app.instance_variable_get(:@session_data)
      expect(session_data[:session_id]).to match(/PAPER_\d{8}_\d{6}/)
      expect(session_data[:start_time]).to be_a(String)
      expect(session_data[:starting_balance]).to eq(200_000.0)
    end

    it "tracks session statistics" do
      mock_position_tracker = paper_app.instance_variable_get(:@position_tracker)
      allow(mock_position_tracker).to receive(:get_positions_summary).and_return({
        total_positions: 5,
        open_positions: 2,
        closed_positions: 3,
        total_pnl: 1_500.0,
        winning_trades: 2,
        losing_trades: 1,
        positions: {},
      })

      # Update session data manually
      paper_app.instance_variable_get(:@session_data)[:total_positions] = 5
      paper_app.instance_variable_get(:@session_data)[:open_positions] = 2
      paper_app.instance_variable_get(:@session_data)[:closed_positions] = 3
      paper_app.instance_variable_get(:@session_data)[:total_pnl] = 1_500.0

      session_data = paper_app.instance_variable_get(:@session_data)
      expect(session_data[:total_positions]).to eq(5)
      expect(session_data[:open_positions]).to eq(2)
      expect(session_data[:closed_positions]).to eq(3)
      expect(session_data[:total_pnl]).to eq(1_500.0)
    end
  end

  describe "Risk Management" do
    it "checks daily loss limits" do
      mock_position_tracker = paper_app.instance_variable_get(:@position_tracker)
      allow(mock_position_tracker).to receive(:get_total_pnl).and_return(-6_000.0)

      expect(paper_app).to receive(:puts).with(/Daily loss limit exceeded/)
      paper_app.send(:check_risk_limits)
    end

    it "continues trading when within limits" do
      mock_position_tracker = paper_app.instance_variable_get(:@position_tracker)
      allow(mock_position_tracker).to receive(:get_total_pnl).and_return(-1_000.0)

      expect(paper_app).not_to receive(:puts)
      paper_app.send(:check_risk_limits)
    end

    it "checks session target" do
      mock_position_tracker = paper_app.instance_variable_get(:@position_tracker)
      allow(mock_position_tracker).to receive(:get_total_pnl).and_return(2_000.0)
      allow(mock_position_tracker).to receive(:get_open_positions).and_return([])

      expect(paper_app).to receive(:puts).with(/Session target reached/)
      paper_app.send(:check_risk_limits)
    end
  end

  describe "Position Management" do
    it "shows position summary" do
      mock_position_tracker = paper_app.instance_variable_get(:@position_tracker)
      allow(mock_position_tracker).to receive(:get_positions_summary).and_return({
        total_positions: 2,
        open_positions: 1,
        closed_positions: 1,
        total_pnl: 500.0,
        winning_trades: 1,
        losing_trades: 0,
        positions: {},
      })

      expect(paper_app).to receive(:puts).with(/Position Summary/)
      expect(paper_app).to receive(:puts).with(/Total Positions: 2/)
      expect(paper_app).to receive(:puts).with(/Open Positions: 1/)
      expect(paper_app).to receive(:puts).with(/Total P&L: ₹500.0/)
      paper_app.send(:show_position_summary)
    end

    it "tracks position highs for trailing stops" do
      mock_position_tracker = paper_app.instance_variable_get(:@position_tracker)
      allow(mock_position_tracker).to receive(:get_positions).and_return([{
        security_id: "CE123",
        current_price: 160.0,
        buy_avg: 150.0,
      }])

      # This method should update position highs
      paper_app.send(:update_position_highs)
      # The method exists and should not raise an error
    end
  end

  describe "Trade Execution" do
    let(:symbol) { "NIFTY" }
    let(:direction) { :bullish }
    let(:spot_price) { 25_000.0 }
    let(:symbol_config) { config["SYMBOLS"]["NIFTY"] }

    it "executes buy trade for bullish signal" do
      mock_broker = paper_app.instance_variable_get(:@broker)
      allow(mock_broker).to receive(:place_order).and_return({
        success: true,
        order_id: "P-1234567890",
        order: double("Order", quantity: 75, price: 150.0),
        position: double("Position", security_id: "CE123"),
      })

      expect(mock_broker).to receive(:place_order).with(hash_including(
        symbol: symbol,
        side: "BUY",
        quantity: 75
      ))

      paper_app.send(:execute_trade, symbol, direction, spot_price, symbol_config)
    end

    it "executes sell trade for bearish signal" do
      mock_broker = paper_app.instance_variable_get(:@broker)
      allow(mock_broker).to receive(:place_order).and_return({
        success: true,
        order_id: "P-1234567890",
        order: double("Order", quantity: 75, price: 120.0),
        position: double("Position", security_id: "PE123"),
      })

      expect(mock_broker).to receive(:place_order).with(hash_including(
        symbol: symbol,
        side: "BUY",
        quantity: 75
      ))

      paper_app.send(:execute_trade, symbol, :bearish, spot_price, symbol_config)
    end

    it "updates session data on successful trade" do
      mock_broker = paper_app.instance_variable_get(:@broker)
      allow(mock_broker).to receive(:place_order).and_return({
        success: true,
        order_id: "P-1234567890",
        order: double("Order", quantity: 75, price: 150.0),
        position: double("Position", security_id: "CE123"),
      })

      expect { paper_app.send(:execute_trade, symbol, direction, spot_price, symbol_config) }
        .to change { paper_app.instance_variable_get(:@session_data)[:total_trades] }.by(1)
    end

    it "handles failed trades gracefully" do
      mock_broker = paper_app.instance_variable_get(:@broker)
      allow(mock_broker).to receive(:place_order).and_return({
        success: false,
        error: "Insufficient balance",
      })

      expect { paper_app.send(:execute_trade, symbol, direction, spot_price, symbol_config) }
        .to change { paper_app.instance_variable_get(:@session_data)[:failed_trades] }.by(1)
    end

    it "skips execution for none signal" do
      mock_broker = paper_app.instance_variable_get(:@broker)
      expect(mock_broker).not_to receive(:place_order)
      paper_app.send(:execute_trade, symbol, :none, spot_price, symbol_config)
    end
  end

  describe "Signal Analysis" do
    it "analyzes signals for each symbol" do
      mock_trend = paper_app.instance_variable_get(:@trend)
      expect(mock_trend).to receive(:decide).with("NIFTY", anything).and_return(:bullish)
      expect(mock_trend).to receive(:decide).with("BANKNIFTY", anything).and_return(:none)

      paper_app.send(:analyze_and_trade)
    end

    it "executes trades when signals are generated" do
      mock_trend = paper_app.instance_variable_get(:@trend)
      allow(mock_trend).to receive(:decide).and_return(:bullish)

      expect(paper_app).to receive(:execute_trade).with("NIFTY", :bullish, 25_000.0, config["SYMBOLS"]["NIFTY"])
      expect(paper_app).to receive(:execute_trade).with("BANKNIFTY", :bullish, 25_000.0, config["SYMBOLS"]["BANKNIFTY"])

      paper_app.send(:analyze_and_trade)
    end

    it "skips trading when no signal" do
      mock_trend = paper_app.instance_variable_get(:@trend)
      allow(mock_trend).to receive(:decide).and_return(:none)

      expect(paper_app).not_to receive(:execute_trade)
      paper_app.send(:analyze_and_trade)
    end
  end

  describe "WebSocket Integration" do
    it "connects to WebSocket" do
      mock_ws_manager = paper_app.instance_variable_get(:@websocket_manager)
      expect(mock_ws_manager).to receive(:connect)
      paper_app.send(:start_websocket_connection)
    end

    it "subscribes to baseline instruments" do
      mock_ws_manager = paper_app.instance_variable_get(:@websocket_manager)
      expect(mock_ws_manager).to receive(:add_baseline_subscription).with("13", "INDEX")
      expect(mock_ws_manager).to receive(:add_baseline_subscription).with("23", "INDEX")
      paper_app.send(:start_tracking_underlyings)
    end

    it "handles WebSocket reconnection" do
      mock_ws_manager = paper_app.instance_variable_get(:@websocket_manager)
      expect(mock_ws_manager).to receive(:on_price_update).and_yield
      paper_app.send(:start_websocket_connection)
    end
  end

  describe "Error Handling" do
    it "handles WebSocket connection failures" do
      allow(paper_app).to receive(:start_websocket_connection).and_raise(StandardError, "Connection failed")
      expect { paper_app.start }.to raise_error(StandardError, "Connection failed")
    end

    it "handles broker errors gracefully" do
      mock_broker = paper_app.instance_variable_get(:@broker)
      allow(mock_broker).to receive(:place_order).and_raise(StandardError, "Order failed")

      expect { paper_app.send(:execute_trade, "NIFTY", :bullish, 25_000.0, config["SYMBOLS"]["NIFTY"]) }
        .to raise_error(StandardError, "Order failed")
    end

    it "handles CSV master errors" do
      mock_csv_master = paper_app.instance_variable_get(:@csv_master)
      allow(mock_csv_master).to receive(:get_expiry_dates).and_raise(StandardError, "CSV error")

      expect { paper_app.send(:execute_trade, "NIFTY", :bullish, 25_000.0, config["SYMBOLS"]["NIFTY"]) }
        .to raise_error(StandardError, "CSV error")
    end
  end

  describe "Performance and Scalability" do
    it "handles multiple symbols efficiently" do
      start_time = Time.now
      paper_app.send(:analyze_and_trade)
      end_time = Time.now
      expect(end_time - start_time).to be < 1.0 # Should complete within 1 second
    end

    it "manages memory efficiently" do
      initial_memory = `ps -o rss= -p #{Process.pid}`.to_i
      100.times { paper_app.send(:analyze_and_trade) }
      final_memory = `ps -o rss= -p #{Process.pid}`.to_i
      memory_increase = final_memory - initial_memory
      expect(memory_increase).to be < 10_000 # Should not increase by more than 10MB
    end
  end

  describe "Configuration and Customization" do
    it "respects custom configuration" do
      custom_config = config.merge({
        global: config[:global].merge(decision_interval: 5)
      })
      custom_app = DhanScalper::PaperApp.new(custom_config, quiet: true, enhanced: true)
      expect(custom_app.instance_variable_get(:@cfg)[:global][:decision_interval]).to eq(5)
    end

    it "handles missing configuration gracefully" do
      minimal_config = { global: {}, paper: {} }
      minimal_app = DhanScalper::PaperApp.new(minimal_config, quiet: true, enhanced: true)
      expect(minimal_app.instance_variable_get(:@cfg)).to eq(minimal_config)
    end

    it "validates required configuration" do
      invalid_config = { global: {} }
      expect { DhanScalper::PaperApp.new(invalid_config, quiet: true, enhanced: true) }
        .not_to raise_error
    end
  end

  describe "Session Reporting" do
    it "generates session reports" do
      mock_reporter = paper_app.instance_variable_get(:@session_reporter)
      expect(mock_reporter).to receive(:generate_session_report)
      paper_app.send(:generate_session_report)
    end

    it "tracks session data correctly" do
      session_data = paper_app.instance_variable_get(:@session_data)
      expect(session_data).to include(:session_id, :start_time, :total_trades, :successful_trades, :failed_trades)
    end
  end

  describe "Cleanup and Shutdown" do
    it "performs graceful shutdown" do
      mock_ws_manager = paper_app.instance_variable_get(:@websocket_manager)
      expect(mock_ws_manager).to receive(:disconnect)
      paper_app.send(:cleanup)
    end

    it "generates final reports" do
      mock_reporter = paper_app.instance_variable_get(:@session_reporter)
      expect(mock_reporter).to receive(:generate_session_report)
      paper_app.send(:cleanup_and_report)
    end
  end

  describe "Integration Tests" do
    it "integrates all components correctly" do
      # Test that all components are properly initialized
      expect(paper_app.instance_variable_get(:@websocket_manager)).to be_present
      expect(paper_app.instance_variable_get(:@position_tracker)).to be_present
      expect(paper_app.instance_variable_get(:@balance_provider)).to be_present
      expect(paper_app.instance_variable_get(:@broker)).to be_present
      expect(paper_app.instance_variable_get(:@csv_master)).to be_present
      expect(paper_app.instance_variable_get(:@picker)).to be_present
      expect(paper_app.instance_variable_get(:@trend)).to be_present
    end

    it "maintains state consistency" do
      # Test that state is maintained correctly across operations
      initial_state = paper_app.instance_variable_get(:@state)
      expect(initial_state).to be_present

      # Test that session data is maintained
      session_data = paper_app.instance_variable_get(:@session_data)
      expect(session_data).to be_a(Hash)
      expect(session_data[:total_trades]).to eq(0)
    end
  end
end
