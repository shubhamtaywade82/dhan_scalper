# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Paper Mode Comprehensive Test Suite" do
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
  let(:mock_redis) { double("Redis") }
  let(:mock_websocket_manager) { double("ResilientWebSocketManager") }
  let(:mock_position_tracker) { double("EnhancedPositionTracker") }
  let(:mock_balance_provider) { double("PaperWallet") }
  let(:mock_broker) { double("PaperBroker") }
  let(:mock_csv_master) { double("CsvMaster") }
  let(:mock_option_picker) { double("OptionPicker") }
  let(:mock_trend_analyzer) { double("TrendEnhanced") }
  let(:mock_risk_manager) { double("UnifiedRiskManager") }
  let(:mock_session_guard) { double("SessionGuard") }

  before do
    # Mock Redis
    allow(Redis).to receive(:new).and_return(mock_redis)
    allow(mock_redis).to receive(:ping).and_return("PONG")
    allow(mock_redis).to receive(:hset)
    allow(mock_redis).to receive(:hgetall).and_return({})
    allow(mock_redis).to receive(:sadd)
    allow(mock_redis).to receive(:smembers).and_return([])
    allow(mock_redis).to receive(:expire)
    allow(mock_redis).to receive(:multi).and_yield(mock_redis)

    # Mock DhanHQ
    allow(DhanHQ).to receive(:configure_with_env)
    allow(DhanHQ).to receive(:logger).and_return(double("Logger", level: 0, "level=": nil))
    allow(DhanHQ).to receive(:configure)
    allow(DhanScalper::Services::DhanHQConfig).to receive(:configure)

    # Mock WebSocket Manager
    allow(mock_websocket_manager).to receive(:start)
    allow(mock_websocket_manager).to receive(:connected?).and_return(true)
    allow(mock_websocket_manager).to receive(:on_price_update)
    allow(mock_websocket_manager).to receive(:on_reconnect)
    allow(mock_websocket_manager).to receive(:add_baseline_subscription)
    allow(mock_websocket_manager).to receive(:add_position_subscription)
    allow(mock_websocket_manager).to receive(:disconnect)
    allow(mock_websocket_manager).to receive(:stop)
    allow(mock_websocket_manager).to receive(:get_subscription_stats).and_return({
                                                                                   connected: true,
                                                                                   total_subscriptions: 2,
                                                                                   baseline_subscriptions: 2,
                                                                                   position_subscriptions: 0,
                                                                                   reconnect_attempts: 0,
                                                                                 })

    # Mock Position Tracker
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
                                                                               })
    allow(mock_position_tracker).to receive(:add_position)
    allow(mock_position_tracker).to receive(:update_all_positions)
    allow(mock_position_tracker).to receive(:get_underlying_price).and_return(25_000.0)

    # Mock Balance Provider
    allow(mock_balance_provider).to receive(:available_balance).and_return(200_000.0)
    allow(mock_balance_provider).to receive(:total_balance).and_return(200_000.0)
    allow(mock_balance_provider).to receive(:debit_for_buy)
    allow(mock_balance_provider).to receive(:update_balance)
    allow(mock_balance_provider).to receive(:add_realized_pnl)

    # Mock Broker
    allow(mock_broker).to receive(:place_order).and_return({
                                                             success: true,
                                                             order_id: "P-#{Time.now.to_f}",
                                                             order: double("Order", id: "P-#{Time.now.to_f}", quantity: 75, price: 150.0),
                                                             position: double("Position", security_id: "TEST123"),
                                                           })
    allow(mock_broker).to receive(:buy_market)
    allow(mock_broker).to receive(:sell_market)

    # Mock CSV Master
    allow(mock_csv_master).to receive(:get_expiry_dates).and_return(["2024-12-26"])
    allow(mock_csv_master).to receive(:get_security_id).and_return("TEST123")
    allow(mock_csv_master).to receive(:get_lot_size).and_return(75)
    allow(mock_csv_master).to receive(:get_available_strikes).and_return([24_500, 24_550, 24_600, 24_650, 24_700, 24_750, 24_800, 24_850, 24_900, 24_950, 25_000, 25_050, 25_100, 25_150, 25_200, 25_250, 25_300, 25_350, 25_400, 25_450, 25_500])

    # Mock Option Picker
    allow(mock_option_picker).to receive(:pick).and_return({
                                                             ce: { strike: 25_000, security_id: "CE123", premium: 150.0 },
                                                             pe: { strike: 25_000, security_id: "PE123", premium: 120.0 },
                                                           })
    allow(mock_option_picker).to receive(:nearest_strike).and_return(25_000)
    allow(mock_option_picker).to receive(:select_strike_for_signal).and_return(25_000)

    # Mock Trend Analyzer
    allow(mock_trend_analyzer).to receive(:decide).and_return(:bullish)
    allow(mock_trend_analyzer).to receive(:analyze).and_return({
                                                                 signal: :bullish,
                                                                 strength: 0.75,
                                                                 adx: 28.5,
                                                                 bias: :bullish,
                                                               })

    # Mock Risk Manager
    allow(mock_risk_manager).to receive(:start)
    allow(mock_risk_manager).to receive(:stop)
    allow(mock_risk_manager).to receive(:check_all_positions)
    allow(mock_risk_manager).to receive(:day_loss_limit_breached?).and_return(false)

    # Mock Session Guard
    allow(mock_session_guard).to receive(:call).and_return(:ok)
    allow(mock_session_guard).to receive(:force_exit_all)

    # Set instance variables
    paper_app.instance_variable_set(:@websocket_manager, mock_websocket_manager)
    paper_app.instance_variable_set(:@position_tracker, mock_position_tracker)
    paper_app.instance_variable_set(:@balance_provider, mock_balance_provider)
    paper_app.instance_variable_set(:@broker, mock_broker)
    paper_app.instance_variable_set(:@csv_master, mock_csv_master)
    paper_app.instance_variable_set(:@picker, mock_option_picker)
    paper_app.instance_variable_set(:@trend, mock_trend_analyzer)
    paper_app.instance_variable_set(:@risk_manager, mock_risk_manager)
    paper_app.instance_variable_set(:@session_guard, mock_session_guard)

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
      expect(paper_app.instance_variable_get(:@websocket_manager)).to eq(mock_websocket_manager)
      expect(paper_app.instance_variable_get(:@position_tracker)).to eq(mock_position_tracker)
      expect(paper_app.instance_variable_get(:@balance_provider)).to eq(mock_balance_provider)
      expect(paper_app.instance_variable_get(:@broker)).to eq(mock_broker)
    end
  end

  describe "WebSocket Connection Management" do
    it "establishes WebSocket connection" do
      expect(mock_websocket_manager).to receive(:start)
      paper_app.send(:start_websocket_connection)
    end

    it "subscribes to baseline instruments" do
      expect(mock_websocket_manager).to receive(:add_baseline_subscription).with("13", "INDEX")
      expect(mock_websocket_manager).to receive(:add_baseline_subscription).with("23", "INDEX")
      paper_app.send(:start_tracking_underlyings)
    end

    it "handles WebSocket reconnection" do
      expect(mock_websocket_manager).to receive(:on_reconnect).and_yield
      expect(paper_app).to receive(:resubscribe_to_positions)
      paper_app.send(:start_websocket_connection)
    end

    it "processes tick data correctly" do
      tick_data = {
        security_id: "13",
        last_price: 25_100.0,
        open: 25_000.0,
        high: 25_150.0,
        low: 24_950.0,
        close: 25_100.0,
        volume: 1_000,
        ts: Time.now.to_i,
      }

      expect(DhanScalper::TickCache).to receive(:put).with(hash_including(
                                                             security_id: "13",
                                                             ltp: 25_100.0,
                                                             segment: "IDX_I",
                                                           ))
      expect(mock_position_tracker).to receive(:update_all_positions)

      paper_app.send(:handle_tick_data, tick_data)
    end
  end

  describe "Signal Analysis and Trading" do
    it "analyzes signals for each symbol" do
      expect(mock_trend_analyzer).to receive(:decide).with("NIFTY", anything).and_return(:bullish)
      expect(mock_trend_analyzer).to receive(:decide).with("BANKNIFTY", anything).and_return(:none)
      paper_app.send(:analyze_and_trade)
    end

    it "executes trades when signals are generated" do
      allow(mock_trend_analyzer).to receive(:decide).and_return(:bullish)
      expect(paper_app).to receive(:execute_trade).with("NIFTY", :bullish, 25_000.0, config["SYMBOLS"]["NIFTY"])
      expect(paper_app).to receive(:execute_trade).with("BANKNIFTY", :bullish, 25_000.0, config["SYMBOLS"]["BANKNIFTY"])
      paper_app.send(:analyze_and_trade)
    end

    it "skips trading when no signal" do
      allow(mock_trend_analyzer).to receive(:decide).and_return(:none)
      expect(paper_app).not_to receive(:execute_trade)
      paper_app.send(:analyze_and_trade)
    end

    it "handles bearish signals correctly" do
      allow(mock_trend_analyzer).to receive(:decide).and_return(:bearish)
      expect(paper_app).to receive(:execute_trade).with("NIFTY", :bearish, 25_000.0, config["SYMBOLS"]["NIFTY"])
      paper_app.send(:analyze_and_trade)
    end
  end

  describe "Trade Execution" do
    let(:symbol) { "NIFTY" }
    let(:direction) { :bullish }
    let(:spot_price) { 25_000.0 }
    let(:symbol_config) { config["SYMBOLS"]["NIFTY"] }

    it "executes buy trade for bullish signal" do
      expect(mock_option_picker).to receive(:pick).with(current_spot: spot_price)
      expect(mock_broker).to receive(:place_order).with(hash_including(
                                                          symbol: symbol,
                                                          side: "BUY",
                                                          quantity: 75,
                                                        ))
      expect(mock_websocket_manager).to receive(:add_position_subscription).with("CE123", "OPTION")
      expect(mock_position_tracker).to receive(:add_position)

      paper_app.send(:execute_trade, symbol, direction, spot_price, symbol_config)
    end

    it "executes sell trade for bearish signal" do
      expect(mock_option_picker).to receive(:pick).with(current_spot: spot_price)
      expect(mock_broker).to receive(:place_order).with(hash_including(
                                                          symbol: symbol,
                                                          side: "BUY",
                                                          quantity: 75,
                                                        ))
      expect(mock_websocket_manager).to receive(:add_position_subscription).with("PE123", "OPTION")
      expect(mock_position_tracker).to receive(:add_position)

      paper_app.send(:execute_trade, symbol, :bearish, spot_price, symbol_config)
    end

    it "updates session data on successful trade" do
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
      allow(mock_broker).to receive(:place_order).and_return({
                                                               success: false,
                                                               error: "Insufficient balance",
                                                             })

      expect { paper_app.send(:execute_trade, symbol, direction, spot_price, symbol_config) }
        .to change { paper_app.instance_variable_get(:@session_data)[:failed_trades] }.by(1)
    end

    it "skips execution for none signal" do
      expect(mock_broker).not_to receive(:place_order)
      paper_app.send(:execute_trade, symbol, :none, spot_price, symbol_config)
    end
  end

  describe "Position Management" do
    let(:position_data) do
      {
        exchange_segment: "NSE_FNO",
        security_id: "CE123",
        side: "LONG",
        buy_qty: 75,
        buy_avg: 150.0,
        net_qty: 75,
        current_price: 160.0,
        unrealized_pnl: 750.0,
      }
    end

    it "adds new positions correctly" do
      expect(mock_position_tracker).to receive(:add_position).with(hash_including(
                                                                     exchange_segment: "NSE_FNO",
                                                                     security_id: "CE123",
                                                                     side: "LONG",
                                                                     quantity: 75,
                                                                     price: 150.0,
                                                                   ))

      paper_app.send(:add_position, position_data)
    end

    it "updates existing positions" do
      allow(mock_position_tracker).to receive(:get_position).and_return(position_data)
      expect(mock_position_tracker).to receive(:update_existing_position).with(anything, anything, anything, anything)

      paper_app.send(:update_position, position_data)
    end

    it "calculates PnL correctly" do
      allow(mock_position_tracker).to receive(:get_positions).and_return([position_data])
      allow(mock_position_tracker).to receive(:get_total_pnl).and_return(750.0)

      pnl = paper_app.send(:calculate_total_pnl)
      expect(pnl).to eq(750.0)
    end

    it "tracks position highs for trailing stops" do
      allow(mock_position_tracker).to receive(:get_positions).and_return([position_data])
      expect(paper_app).to receive(:update_position_high).with("CE123", 160.0)

      paper_app.send(:update_position_highs)
    end
  end

  describe "Risk Management" do
    it "checks daily loss limits" do
      allow(mock_position_tracker).to receive(:get_total_pnl).and_return(-6_000.0)
      expect(paper_app).to receive(:puts).with(/Daily loss limit breached/)
      paper_app.send(:check_risk_limits)
    end

    it "continues trading when within limits" do
      allow(mock_position_tracker).to receive(:get_total_pnl).and_return(-1_000.0)
      expect(paper_app).not_to receive(:puts)
      paper_app.send(:check_risk_limits)
    end

    it "applies trailing stops correctly" do
      position_data = {
        security_id: "CE123",
        buy_avg: 150.0,
        current_price: 180.0,
        peak_price: 180.0,
      }

      allow(mock_position_tracker).to receive(:get_positions).and_return([position_data])
      expect(mock_risk_manager).to receive(:check_all_positions)

      paper_app.send(:apply_risk_management)
    end

    it "handles emergency exits" do
      allow(mock_session_guard).to receive(:call).and_return(:panic_switch)
      expect(mock_session_guard).to receive(:force_exit_all)

      result = paper_app.send(:check_session_limits)
      expect(result).to be true
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
      allow(mock_position_tracker).to receive(:get_positions_summary).and_return({
                                                                                   total_positions: 5,
                                                                                   open_positions: 2,
                                                                                   closed_positions: 3,
                                                                                   total_pnl: 1_500.0,
                                                                                   winning_trades: 2,
                                                                                   losing_trades: 1,
                                                                                 })

      paper_app.send(:update_session_stats)

      session_data = paper_app.instance_variable_get(:@session_data)
      expect(session_data[:total_positions]).to eq(5)
      expect(session_data[:open_positions]).to eq(2)
      expect(session_data[:closed_positions]).to eq(3)
      expect(session_data[:total_pnl]).to eq(1_500.0)
    end

    it "generates session reports" do
      mock_reporter = double("SessionReporter")
      allow(mock_reporter).to receive(:generate_session_report)
      paper_app.instance_variable_set(:@reporter, mock_reporter)

      expect(mock_reporter).to receive(:generate_session_report)
      paper_app.send(:generate_session_report)
    end
  end

  describe "Market Hours and Session Guards" do
    it "respects market hours" do
      allow(Time).to receive(:now).and_return(Time.parse("2024-01-15 08:00:00")) # Before market hours
      expect(paper_app).to receive(:puts).with(/Market is closed/)
      paper_app.send(:check_market_hours)
    end

    it "allows trading during market hours" do
      allow(Time).to receive(:now).and_return(Time.parse("2024-01-15 10:30:00")) # During market hours
      expect(paper_app).not_to receive(:puts)
      paper_app.send(:check_market_hours)
    end

    it "checks session guard status" do
      expect(mock_session_guard).to receive(:call).and_return(:ok)
      result = paper_app.send(:check_session_limits)
      expect(result).to be false
    end

    it "handles day loss limit breach" do
      allow(mock_session_guard).to receive(:call).and_return(:day_loss_limit)
      expect(mock_session_guard).to receive(:force_exit_all)
      result = paper_app.send(:check_session_limits)
      expect(result).to be true
    end
  end

  describe "Error Handling and Recovery" do
    it "handles WebSocket connection failures" do
      allow(paper_app).to receive(:start_websocket_connection).and_raise(StandardError, "Connection failed")
      expect { paper_app.start }.to raise_error(StandardError, "Connection failed")
    end

    it "handles broker errors gracefully" do
      allow(mock_broker).to receive(:place_order).and_raise(StandardError, "Order failed")
      expect { paper_app.send(:execute_trade, "NIFTY", :bullish, 25_000.0, config["SYMBOLS"]["NIFTY"]) }
        .to raise_error(StandardError, "Order failed")
    end

    it "handles CSV master errors" do
      allow(mock_csv_master).to receive(:get_expiry_dates).and_raise(StandardError, "CSV error")
      expect { paper_app.send(:execute_trade, "NIFTY", :bullish, 25_000.0, config["SYMBOLS"]["NIFTY"]) }
        .to raise_error(StandardError, "CSV error")
    end

    it "handles position tracker errors" do
      allow(mock_position_tracker).to receive(:add_position).and_raise(StandardError, "Position error")
      expect { paper_app.send(:add_position, {}) }
        .to raise_error(StandardError, "Position error")
    end

    it "recovers from temporary failures" do
      allow(mock_websocket_manager).to receive(:connected?).and_return(false, true)
      expect(mock_websocket_manager).to receive(:start)
      paper_app.send(:ensure_websocket_connection)
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

    it "handles high-frequency updates" do
      tick_data = {
        security_id: "13",
        last_price: 25_100.0,
        ts: Time.now.to_i,
      }

      start_time = Time.now
      1_000.times { paper_app.send(:handle_tick_data, tick_data) }
      end_time = Time.now
      expect(end_time - start_time).to be < 5.0 # Should handle 1000 ticks within 5 seconds
    end
  end

  describe "Integration with External Services" do
    it "integrates with Redis correctly" do
      expect(mock_redis).to receive(:hset).with(anything, anything, anything)
      paper_app.send(:store_position_data, "test_position", {})
    end

    it "integrates with WebSocket manager" do
      expect(mock_websocket_manager).to receive(:add_baseline_subscription).with("13", "INDEX")
      paper_app.send(:start_tracking_underlyings)
    end

    it "integrates with risk manager" do
      expect(mock_risk_manager).to receive(:start)
      paper_app.send(:start_risk_management)
    end

    it "integrates with session guard" do
      expect(mock_session_guard).to receive(:call).and_return(:ok)
      paper_app.send(:check_session_limits)
    end
  end

  describe "Configuration and Customization" do
    it "respects custom configuration" do
      custom_config = config.merge({
                                     global: config[:global].merge(decision_interval: 5),
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

  describe "Logging and Monitoring" do
    it "logs important events" do
      expect(paper_app).to receive(:puts).with(/Starting paper trading mode/)
      paper_app.send(:log_startup_message)
    end

    it "logs position updates" do
      expect(paper_app).to receive(:puts).with(/Position added/)
      paper_app.send(:log_position_update, { security_id: "CE123", action: "added" })
    end

    it "logs error events" do
      expect(paper_app).to receive(:puts).with(/Error: Test error/)
      paper_app.send(:log_error, "Test error")
    end

    it "provides status information" do
      allow(mock_position_tracker).to receive(:get_positions_summary).and_return({
                                                                                   total_positions: 1,
                                                                                   open_positions: 1,
                                                                                   total_pnl: 500.0,
                                                                                 })

      expect(paper_app).to receive(:puts).with(/Status/)
      paper_app.send(:show_status)
    end
  end

  describe "Cleanup and Shutdown" do
    it "performs graceful shutdown" do
      expect(mock_websocket_manager).to receive(:disconnect)
      expect(mock_risk_manager).to receive(:stop)
      paper_app.send(:cleanup)
    end

    it "generates final reports" do
      mock_reporter = double("SessionReporter")
      allow(mock_reporter).to receive(:generate_session_report)
      paper_app.instance_variable_set(:@reporter, mock_reporter)

      expect(mock_reporter).to receive(:generate_session_report)
      paper_app.send(:cleanup_and_report)
    end

    it "saves session data" do
      expect(mock_redis).to receive(:hset).with(anything, anything, anything)
      paper_app.send(:save_session_data)
    end
  end
end
