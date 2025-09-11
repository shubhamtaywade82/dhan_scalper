# frozen_string_literal: true

require "spec_helper"

RSpec.describe DhanScalper::PaperApp, :unit do
  let(:base_config) do
    {
      "global" => {
        "min_profit_target" => 1000,
        "max_day_loss" => 5000,
        "decision_interval" => 10,
        "log_level" => "INFO",
        "use_multi_timeframe" => true,
        "secondary_timeframe" => 5
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

  let(:paper_app) { described_class.new(base_config, quiet: true, enhanced: true) }

  before do
    setup_comprehensive_mocks
  end

  def setup_comprehensive_mocks
    # Mock WebSocket Manager
    @mock_ws_manager = double("WebSocketManager")
    allow(@mock_ws_manager).to receive(:connect)
    allow(@mock_ws_manager).to receive(:connected?).and_return(true)
    allow(@mock_ws_manager).to receive(:on_price_update)
    allow(@mock_ws_manager).to receive(:subscribe_to_instrument)
    allow(@mock_ws_manager).to receive(:unsubscribe_from_instrument)
    allow(paper_app).to receive(:instance_variable_get).with(:@websocket_manager).and_return(@mock_ws_manager)

    # Mock Position Tracker
    @mock_position_tracker = double("PaperPositionTracker")
    allow(@mock_position_tracker).to receive(:setup_websocket_handlers)
    allow(@mock_position_tracker).to receive(:get_total_pnl).and_return(0.0)
    allow(@mock_position_tracker).to receive(:get_positions_summary).and_return({
      total_positions: 0,
      open_positions: 0,
      closed_positions: 0,
      total_pnl: 0.0,
      session_pnl: 0.0
    })
    allow(@mock_position_tracker).to receive(:get_session_stats).and_return({
      total_trades: 0,
      winning_trades: 0,
      losing_trades: 0,
      win_rate: 0.0,
      total_pnl: 0.0,
      max_profit: 0.0,
      max_drawdown: 0.0
    })
    allow(@mock_position_tracker).to receive(:track_underlying)
    allow(@mock_position_tracker).to receive(:add_position)
    allow(@mock_position_tracker).to receive(:get_open_positions).and_return([])
    allow(paper_app).to receive(:instance_variable_get).with(:@position_tracker).and_return(@mock_position_tracker)

    # Mock Balance Provider
    @mock_balance_provider = double("PaperWallet")
    allow(@mock_balance_provider).to receive(:available_balance).and_return(200_000.0)
    allow(@mock_balance_provider).to receive(:total_balance).and_return(200_000.0)
    allow(@mock_balance_provider).to receive(:used_balance).and_return(0.0)
    allow(@mock_balance_provider).to receive(:update_balance)
    allow(paper_app).to receive(:instance_variable_get).with(:@balance_provider).and_return(@mock_balance_provider)

    # Mock CSV Master
    @mock_csv_master = double("CsvMaster")
    allow(@mock_csv_master).to receive(:get_expiry_dates).and_return(["2024-12-26"])
    allow(@mock_csv_master).to receive(:get_security_id).and_return("TEST123")
    allow(@mock_csv_master).to receive(:get_lot_size).and_return(75)
    allow(@mock_csv_master).to receive(:get_available_strikes).and_return([25000, 25050, 25100])
    allow(paper_app).to receive(:instance_variable_get).with(:@csv_master).and_return(@mock_csv_master)

    # Mock TickCache
    allow(DhanScalper::TickCache).to receive(:ltp).and_return(25000.0)
    allow(DhanScalper::TickCache).to receive(:get).and_return({
      last_price: 25000.0,
      timestamp: Time.now.to_i
    })

    # Mock CandleSeries
    mock_candle_series = double("CandleSeries")
    allow(mock_candle_series).to receive(:holy_grail).and_return({
      bias: :bullish,
      momentum: :strong,
      adx: 25.0,
      rsi: 65.0,
      macd: :bullish
    })
    allow(mock_candle_series).to receive(:supertrend_signal).and_return(:bullish)
    allow(mock_candle_series).to receive(:combined_signal).and_return(:bullish)
    allow(DhanScalper::CandleSeries).to receive(:load_from_dhan_intraday).and_return(mock_candle_series)

    # Mock Option Picker
    @mock_option_picker = double("OptionPicker")
    allow(@mock_option_picker).to receive(:pick).and_return({
      ce: { security_id: "CE123", premium: 100.0 },
      pe: { security_id: "PE123", premium: 80.0 }
    })
    allow(@mock_option_picker).to receive(:pick_atm_strike).and_return({
      ce: { security_id: "CE123", premium: 100.0, strike: 25000 },
      pe: { security_id: "PE123", premium: 80.0, strike: 25000 }
    })
    allow(paper_app).to receive(:instance_variable_get).with(:@option_pickers).and_return({
      "NIFTY" => @mock_option_picker
    })

    # Mock Paper Broker
    @mock_paper_broker = double("PaperBroker")
    allow(@mock_paper_broker).to receive(:buy_market).and_return({
      order_id: "ORDER123",
      status: "FILLED",
      avg_price: 100.0
    })
    allow(@mock_paper_broker).to receive(:sell_market).and_return({
      order_id: "ORDER124",
      status: "FILLED",
      avg_price: 120.0
    })
    allow(paper_app).to receive(:instance_variable_get).with(:@paper_broker).and_return(@mock_paper_broker)
  end

  describe "#initialize" do
    context "with valid configuration" do
      it "initializes with correct attributes" do
        expect(paper_app.instance_variable_get(:@cfg)).to eq(base_config)
        expect(paper_app.instance_variable_get(:@quiet)).to be true
        expect(paper_app.instance_variable_get(:@enhanced)).to be true
      end

      it "sets up timeout correctly" do
        app_with_timeout = described_class.new(base_config, quiet: true, enhanced: true, timeout_minutes: 5)
        expect(app_with_timeout.instance_variable_get(:@timeout_minutes)).to eq(5)
      end
    end

    context "with invalid configuration" do
      it "raises error for missing symbols" do
        invalid_config = base_config.dup
        invalid_config.delete("SYMBOLS")
        
        expect {
          described_class.new(invalid_config, quiet: true, enhanced: true)
        }.to raise_error(KeyError)
      end

      it "raises error for missing global settings" do
        invalid_config = base_config.dup
        invalid_config.delete("global")
        
        expect {
          described_class.new(invalid_config, quiet: true, enhanced: true)
        }.to raise_error(KeyError)
      end
    end
  end

  describe "#start" do
    before do
      allow(paper_app).to receive(:initialize_components)
      allow(paper_app).to receive(:start_websocket_connection)
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

    it "runs main trading loop" do
      expect(paper_app).to receive(:main_trading_loop)
      paper_app.start
    end

    it "performs cleanup on exit" do
      expect(paper_app).to receive(:cleanup_and_report)
      paper_app.start
    end

    context "when timeout is set" do
      let(:timeout_app) { described_class.new(base_config, quiet: true, enhanced: true, timeout_minutes: 1) }

      before do
        allow(timeout_app).to receive(:initialize_components)
        allow(timeout_app).to receive(:start_websocket_connection)
        allow(timeout_app).to receive(:cleanup_and_report)
      end

      it "stops after timeout period" do
        expect(timeout_app).to receive(:main_trading_loop).and_call_original
        allow(timeout_app).to receive(:should_stop_trading?).and_return(true)
        
        timeout_app.start
      end
    end
  end

  describe "#analyze_and_trade" do
    before do
      allow(paper_app).to receive(:get_holy_grail_signal).and_return(:bullish)
      allow(paper_app).to receive(:execute_trade)
    end

    it "analyzes signals for all configured symbols" do
      expect(paper_app).to receive(:get_holy_grail_signal).with("NIFTY")
      paper_app.analyze_and_trade
    end

    it "executes trades when signals are generated" do
      expect(paper_app).to receive(:execute_trade).with("NIFTY", :bullish, 25000.0, base_config["SYMBOLS"]["NIFTY"])
      paper_app.analyze_and_trade
    end

    context "when no signal is generated" do
      before do
        allow(paper_app).to receive(:get_holy_grail_signal).and_return(:none)
      end

      it "does not execute trades" do
        expect(paper_app).not_to receive(:execute_trade)
        paper_app.analyze_and_trade
      end
    end

    context "when market is closed" do
      before do
        allow(paper_app).to receive(:market_open?).and_return(false)
      end

      it "skips trading analysis" do
        expect(paper_app).not_to receive(:get_holy_grail_signal)
        paper_app.analyze_and_trade
      end
    end
  end

  describe "#execute_trade" do
    let(:symbol) { "NIFTY" }
    let(:direction) { :bullish }
    let(:spot_price) { 25000.0 }
    let(:symbol_config) { base_config["SYMBOLS"]["NIFTY"] }

    before do
      allow(paper_app).to receive(:check_risk_limits).and_return(true)
      allow(paper_app).to receive(:get_current_spot_price).and_return(spot_price)
    end

    it "executes buy trade for bullish signal" do
      expect(@mock_option_picker).to receive(:pick_atm_strike).with(spot_price, direction)
      expect(@mock_paper_broker).to receive(:buy_market)
      expect(@mock_position_tracker).to receive(:add_position)
      
      paper_app.execute_trade(symbol, direction, spot_price, symbol_config)
    end

    it "executes sell trade for bearish signal" do
      expect(@mock_option_picker).to receive(:pick_atm_strike).with(spot_price, :bearish)
      expect(@mock_paper_broker).to receive(:sell_market)
      expect(@mock_position_tracker).to receive(:add_position)
      
      paper_app.execute_trade(symbol, :bearish, spot_price, symbol_config)
    end

    context "when risk limits are breached" do
      before do
        allow(paper_app).to receive(:check_risk_limits).and_return(false)
      end

      it "does not execute trade" do
        expect(@mock_paper_broker).not_to receive(:buy_market)
        paper_app.execute_trade(symbol, direction, spot_price, symbol_config)
      end
    end

    context "when option picker fails" do
      before do
        allow(@mock_option_picker).to receive(:pick_atm_strike).and_return(nil)
      end

      it "handles error gracefully" do
        expect { paper_app.execute_trade(symbol, direction, spot_price, symbol_config) }.not_to raise_error
      end
    end
  end

  describe "#check_risk_limits" do
    context "when within limits" do
      before do
        allow(@mock_position_tracker).to receive(:get_total_pnl).and_return(-1000.0)
      end

      it "allows trading" do
        expect(paper_app.check_risk_limits).to be true
      end
    end

    context "when daily loss limit is breached" do
      before do
        allow(@mock_position_tracker).to receive(:get_total_pnl).and_return(-6000.0)
      end

      it "stops trading" do
        expect(paper_app.check_risk_limits).to be false
      end
    end

    context "when profit target is reached" do
      before do
        allow(@mock_position_tracker).to receive(:get_total_pnl).and_return(1500.0)
      end

      it "stops trading" do
        expect(paper_app.check_risk_limits).to be false
      end
    end
  end

  describe "#market_open?" do
    context "during market hours" do
      before do
        allow(Time).to receive(:now).and_return(Time.parse("2024-12-08 10:30:00 IST"))
      end

      it "returns true" do
        expect(paper_app.market_open?).to be true
      end
    end

    context "before market hours" do
      before do
        allow(Time).to receive(:now).and_return(Time.parse("2024-12-08 08:00:00 IST"))
      end

      it "returns false" do
        expect(paper_app.market_open?).to be false
      end
    end

    context "after market hours" do
      before do
        allow(Time).to receive(:now).and_return(Time.parse("2024-12-08 16:00:00 IST"))
      end

      it "returns false" do
        expect(paper_app.market_open?).to be false
      end
    end

    context "on weekends" do
      before do
        allow(Time).to receive(:now).and_return(Time.parse("2024-12-07 10:30:00 IST")) # Saturday
      end

      it "returns false" do
        expect(paper_app.market_open?).to be false
      end
    end
  end

  describe "#get_holy_grail_signal" do
    let(:symbol) { "NIFTY" }
    let(:symbol_config) { base_config["SYMBOLS"]["NIFTY"] }

    before do
      allow(paper_app).to receive(:sym_cfg).with(symbol).and_return(symbol_config)
    end

    it "returns bullish signal for strong bullish indicators" do
      mock_series = double("CandleSeries")
      allow(mock_series).to receive(:holy_grail).and_return({
        bias: :bullish,
        momentum: :strong,
        adx: 30.0,
        rsi: 70.0,
        macd: :bullish
      })
      allow(mock_series).to receive(:supertrend_signal).and_return(:bullish)
      allow(mock_series).to receive(:combined_signal).and_return(:bullish)
      allow(DhanScalper::CandleSeries).to receive(:load_from_dhan_intraday).and_return(mock_series)

      result = paper_app.get_holy_grail_signal(symbol)
      expect(result).to eq(:bullish)
    end

    it "returns bearish signal for strong bearish indicators" do
      mock_series = double("CandleSeries")
      allow(mock_series).to receive(:holy_grail).and_return({
        bias: :bearish,
        momentum: :strong,
        adx: 30.0,
        rsi: 30.0,
        macd: :bearish
      })
      allow(mock_series).to receive(:supertrend_signal).and_return(:bearish)
      allow(mock_series).to receive(:combined_signal).and_return(:bearish)
      allow(DhanScalper::CandleSeries).to receive(:load_from_dhan_intraday).and_return(mock_series)

      result = paper_app.get_holy_grail_signal(symbol)
      expect(result).to eq(:bearish)
    end

    it "returns none for weak signals" do
      mock_series = double("CandleSeries")
      allow(mock_series).to receive(:holy_grail).and_return({
        bias: :neutral,
        momentum: :weak,
        adx: 15.0,
        rsi: 50.0,
        macd: :neutral
      })
      allow(mock_series).to receive(:supertrend_signal).and_return(:none)
      allow(mock_series).to receive(:combined_signal).and_return(:none)
      allow(DhanScalper::CandleSeries).to receive(:load_from_dhan_intraday).and_return(mock_series)

      result = paper_app.get_holy_grail_signal(symbol)
      expect(result).to eq(:none)
    end

    context "when data loading fails" do
      before do
        allow(DhanScalper::CandleSeries).to receive(:load_from_dhan_intraday).and_raise(StandardError, "Data loading failed")
      end

      it "returns none and logs error" do
        expect(paper_app).to receive(:puts).with(/Error loading data for #{symbol}/)
        result = paper_app.get_holy_grail_signal(symbol)
        expect(result).to eq(:none)
      end
    end
  end

  describe "#show_position_summary" do
    before do
      allow(@mock_position_tracker).to receive(:get_positions_summary).and_return({
        total_positions: 2,
        open_positions: 1,
        closed_positions: 1,
        total_pnl: 500.0,
        session_pnl: 300.0
      })
    end

    it "displays position summary" do
      expect(paper_app).to receive(:puts).with(/Position Summary/)
      expect(paper_app).to receive(:puts).with(/Total Positions: 2/)
      expect(paper_app).to receive(:puts).with(/Open Positions: 1/)
      expect(paper_app).to receive(:puts).with(/Closed Positions: 1/)
      expect(paper_app).to receive(:puts).with(/Total P&L: ₹500.00/)
      expect(paper_app).to receive(:puts).with(/Session P&L: ₹300.00/)
      
      paper_app.show_position_summary
    end
  end

  describe "#generate_session_report" do
    before do
      allow(@mock_position_tracker).to receive(:get_session_stats).and_return({
        total_trades: 5,
        winning_trades: 3,
        losing_trades: 2,
        win_rate: 60.0,
        total_pnl: 1000.0,
        max_profit: 800.0,
        max_drawdown: -200.0
      })
      allow(@mock_balance_provider).to receive(:total_balance).and_return(201_000.0)
      allow(@mock_balance_provider).to receive(:available_balance).and_return(150_000.0)
    end

    it "generates comprehensive session report" do
      expect(paper_app).to receive(:puts).with(/SESSION REPORT/)
      expect(paper_app).to receive(:puts).with(/Total Trades: 5/)
      expect(paper_app).to receive(:puts).with(/Win Rate: 60.0%/)
      expect(paper_app).to receive(:puts).with(/Total P&L: ₹1000.00/)
      
      paper_app.generate_session_report
    end
  end

  describe "error handling" do
    context "when WebSocket connection fails" do
      before do
        allow(@mock_ws_manager).to receive(:connect).and_raise(StandardError, "Connection failed")
      end

      it "handles connection errors gracefully" do
        expect { paper_app.start }.not_to raise_error
      end
    end

    context "when position tracker fails" do
      before do
        allow(@mock_position_tracker).to receive(:get_total_pnl).and_raise(StandardError, "Tracker error")
      end

      it "handles tracker errors gracefully" do
        expect { paper_app.check_risk_limits }.not_to raise_error
      end
    end

    context "when broker operations fail" do
      before do
        allow(@mock_paper_broker).to receive(:buy_market).and_raise(StandardError, "Broker error")
      end

      it "handles broker errors gracefully" do
        expect { 
          paper_app.execute_trade("NIFTY", :bullish, 25000.0, base_config["SYMBOLS"]["NIFTY"])
        }.not_to raise_error
      end
    end
  end

  describe "performance characteristics" do
    it "handles high-frequency signal analysis" do
      start_time = Time.now
      
      100.times do
        paper_app.analyze_and_trade
      end
      
      duration = Time.now - start_time
      expect(duration).to be < 1.0 # Should complete within 1 second
    end

    it "manages memory efficiently during long sessions" do
      initial_memory = `ps -o rss= -p #{Process.pid}`.to_i
      
      # Simulate 1000 iterations
      1000.times do
        paper_app.analyze_and_trade
      end
      
      final_memory = `ps -o rss= -p #{Process.pid}`.to_i
      memory_increase = final_memory - initial_memory
      
      # Memory increase should be reasonable (less than 10MB)
      expect(memory_increase).to be < 10_000
    end
  end
end
