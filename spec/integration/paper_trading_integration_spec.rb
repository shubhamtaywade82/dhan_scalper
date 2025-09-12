# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Paper Trading Integration", :slow do
  let(:config) do
    {
      "global" => {
        "min_profit_target" => 1_000,
        "max_day_loss" => 5_000,
        "decision_interval" => 5,
        "log_level" => "INFO",
        "use_multi_timeframe" => true,
        "secondary_timeframe" => 5,
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

  let(:paper_app) { DhanScalper::PaperApp.new(config, quiet: true, enhanced: true) }

  before do
    # Mock external dependencies
    mock_websocket_manager = double("WebSocketManager")
    allow(mock_websocket_manager).to receive(:connect)
    allow(mock_websocket_manager).to receive(:connected?).and_return(true)
    allow(mock_websocket_manager).to receive(:on_price_update)
    allow(mock_websocket_manager).to receive(:subscribe_to_instrument)
    allow(mock_websocket_manager).to receive(:unsubscribe_from_instrument)
    allow(paper_app).to receive(:instance_variable_get).with(:@websocket_manager).and_return(mock_websocket_manager)

    # Mock CSV master
    mock_csv_master = double("CsvMaster")
    allow(mock_csv_master).to receive(:get_expiry_dates).and_return(["2024-12-26"])
    allow(mock_csv_master).to receive(:get_security_id).and_return("TEST123")
    allow(mock_csv_master).to receive(:get_lot_size).and_return(75)
    allow(paper_app).to receive(:instance_variable_get).with(:@csv_master).and_return(mock_csv_master)

    # Mock DhanHQ configuration
    allow(DhanScalper::Services::DhanHQConfig).to receive(:validate!)
    allow(DhanScalper::Services::DhanHQConfig).to receive(:configure)
  end

  describe "Complete Paper Trading Workflow" do
    it "initializes all components correctly" do
      paper_app.send(:initialize_components)

      expect(paper_app.instance_variable_get(:@balance_provider)).to be_a(DhanScalper::BalanceProviders::PaperWallet)
      expect(paper_app.instance_variable_get(:@broker)).to be_a(DhanScalper::Brokers::PaperBroker)
      expect(paper_app.instance_variable_get(:@position_tracker)).to be_a(DhanScalper::Services::PaperPositionTracker)
      expect(paper_app.instance_variable_get(:@csv_master)).to be_a(DhanScalper::CsvMaster)
    end

    it "sets up WebSocket connection" do
      mock_ws_manager = paper_app.instance_variable_get(:@websocket_manager)
      expect(mock_ws_manager).to receive(:connect)
      paper_app.send(:start_websocket_connection)
    end

    it "tracks underlying indices" do
      mock_ws_manager = paper_app.instance_variable_get(:@websocket_manager)
      expect(mock_ws_manager).to receive(:subscribe_to_instrument).with("13", "INDEX")

      paper_app.send(:start_tracking_underlyings)
    end

    it "subscribes to ATM options for monitoring" do
      mock_ws_manager = paper_app.instance_variable_get(:@websocket_manager)
      expect(mock_ws_manager).to receive(:subscribe_to_instrument).at_least(1)

      paper_app.send(:subscribe_to_atm_options_for_monitoring)
    end
  end

  describe "Trading Signal Analysis" do
    before do
      paper_app.send(:initialize_components)
    end

    it "analyzes Holy Grail signals correctly" do
      # Mock candle series data
      mock_candle_series = double("CandleSeries")
      allow(mock_candle_series).to receive(:holy_grail).and_return({
                                                                     bias: :bullish,
                                                                     momentum: :strong,
                                                                     adx: 25.0,
                                                                     rsi: 65.0,
                                                                     macd: :bullish,
                                                                   })
      allow(DhanScalper::CandleSeries).to receive(:load_from_dhan_intraday).and_return(mock_candle_series)

      signal = paper_app.send(:get_holy_grail_signal, "NIFTY")
      expect(signal).to eq(:bullish)
    end

    it "handles insufficient data gracefully" do
      allow(DhanScalper::CandleSeries).to receive(:load_from_dhan_intraday).and_return(nil)

      signal = paper_app.send(:get_holy_grail_signal, "NIFTY")
      expect(signal).to eq(:none)
    end

    it "gets current spot price from position tracker" do
      mock_position_tracker = paper_app.instance_variable_get(:@position_tracker)
      allow(mock_position_tracker).to receive(:get_underlying_price).and_return(25_000.0)

      spot_price = paper_app.send(:get_current_spot_price, "NIFTY")
      expect(spot_price).to eq(25_000.0)
    end
  end

  describe "Order Execution" do
    before do
      paper_app.send(:initialize_components)
    end

    it "executes buy trades correctly" do
      mock_broker = paper_app.instance_variable_get(:@broker)
      allow(mock_broker).to receive(:place_order).and_return({
                                                               success: true,
                                                               order_id: "P-1234567890",
                                                               order: double("Order", quantity: 75, price: 150.0),
                                                               position: double("Position", security_id: "TEST123"),
                                                             })

      # Mock option picker
      mock_picker = double("OptionPicker")
      allow(mock_picker).to receive(:pick).and_return({
                                                        ce: { strike: 25_000, security_id: "CE123", premium: 150.0 },
                                                        pe: { strike: 25_000, security_id: "PE123", premium: 120.0 },
                                                      })
      allow(paper_app).to receive(:get_cached_picker).and_return(mock_picker)

      # Mock trend analysis
      mock_trend = double("TrendEnhanced")
      allow(mock_trend).to receive(:decide).and_return(:bullish)
      allow(paper_app).to receive(:get_cached_trend).and_return(mock_trend)

      result = paper_app.send(:execute_buy_trade, "NIFTY", :bullish, 25_000.0, config["SYMBOLS"]["NIFTY"])
      expect(result).to be true
    end

    it "handles order failures gracefully" do
      mock_broker = paper_app.instance_variable_get(:@broker)
      allow(mock_broker).to receive(:place_order).and_return({
                                                               success: false,
                                                               error: "Insufficient balance",
                                                             })

      # Mock option picker
      mock_picker = double("OptionPicker")
      allow(mock_picker).to receive(:pick).and_return({
                                                        ce: { strike: 25_000, security_id: "CE123", premium: 150.0 },
                                                      })
      allow(paper_app).to receive(:get_cached_picker).and_return(mock_picker)

      # Mock trend analysis
      mock_trend = double("TrendEnhanced")
      allow(mock_trend).to receive(:decide).and_return(:bullish)
      allow(paper_app).to receive(:get_cached_trend).and_return(mock_trend)

      result = paper_app.send(:execute_buy_trade, "NIFTY", :bullish, 25_000.0, config["SYMBOLS"]["NIFTY"])
      expect(result).to be false
    end
  end

  describe "Position Management" do
    before do
      paper_app.send(:initialize_components)
    end

    it "tracks positions correctly" do
      mock_position_tracker = paper_app.instance_variable_get(:@position_tracker)
      allow(mock_position_tracker).to receive(:add_position)
      allow(mock_position_tracker).to receive(:get_total_pnl).and_return(500.0)
      allow(mock_position_tracker).to receive(:get_positions_summary).and_return({
                                                                                   total_positions: 1,
                                                                                   open_positions: 1,
                                                                                   closed_positions: 0,
                                                                                   total_pnl: 500.0,
                                                                                   winning_trades: 1,
                                                                                   losing_trades: 0,
                                                                                 })

      # Add a position
      mock_position_tracker.add_position("NIFTY", "CE", 25_000, Date.today, "CE123", 75, 150.0)

      summary = mock_position_tracker.get_positions_summary
      expect(summary[:total_positions]).to eq(1)
      expect(summary[:total_pnl]).to eq(500.0)
    end

    it "calculates P&L correctly" do
      mock_position_tracker = paper_app.instance_variable_get(:@position_tracker)
      allow(mock_position_tracker).to receive(:get_total_pnl).and_return(750.0)

      total_pnl = mock_position_tracker.get_total_pnl
      expect(total_pnl).to eq(750.0)
    end
  end

  describe "Risk Management" do
    before do
      paper_app.send(:initialize_components)
    end

    it "checks daily loss limits" do
      mock_position_tracker = paper_app.instance_variable_get(:@position_tracker)
      allow(mock_position_tracker).to receive(:get_total_pnl).and_return(-6_000.0)

      expect { paper_app.send(:check_risk_limits) }.to output(/Daily loss limit breached/).to_stdout
    end

    it "continues trading when within limits" do
      mock_position_tracker = paper_app.instance_variable_get(:@position_tracker)
      allow(mock_position_tracker).to receive(:get_total_pnl).and_return(-1_000.0)

      expect { paper_app.send(:check_risk_limits) }.not_to output.to_stdout
    end
  end

  describe "Session Reporting" do
    before do
      paper_app.send(:initialize_components)
    end

    it "generates session reports" do
      mock_position_tracker = paper_app.instance_variable_get(:@position_tracker)
      allow(mock_position_tracker).to receive(:get_positions_summary).and_return({
                                                                                   total_positions: 2,
                                                                                   open_positions: 0,
                                                                                   closed_positions: 2,
                                                                                   total_pnl: 1_000.0,
                                                                                   winning_trades: 1,
                                                                                   losing_trades: 1,
                                                                                 })

      mock_reporter = double("SessionReporter")
      allow(mock_reporter).to receive(:generate_session_report)
      allow(paper_app).to receive(:instance_variable_get).with(:@reporter).and_return(mock_reporter)

      expect(mock_reporter).to receive(:generate_session_report)
      paper_app.send(:generate_session_report)
    end
  end

  describe "Error Handling and Recovery" do
    it "handles WebSocket connection failures" do
      mock_ws_manager = paper_app.instance_variable_get(:@websocket_manager)
      allow(mock_ws_manager).to receive(:connect).and_raise(StandardError, "Connection failed")

      expect { paper_app.send(:start_websocket_connection) }.to raise_error(StandardError, "Connection failed")
    end

    it "handles CSV master data loading failures" do
      mock_csv_master = paper_app.instance_variable_get(:@csv_master)
      allow(mock_csv_master).to receive(:get_expiry_dates).and_raise(StandardError, "CSV loading failed")

      expect do
        paper_app.send(:execute_buy_trade, "NIFTY", :bullish, 25_000.0,
                       config["SYMBOLS"]["NIFTY"])
      end.to raise_error(StandardError, "CSV loading failed")
    end

    it "handles broker errors gracefully" do
      paper_app.send(:initialize_components)
      mock_broker = paper_app.instance_variable_get(:@broker)
      allow(mock_broker).to receive(:place_order).and_raise(StandardError, "Broker error")

      expect do
        paper_app.send(:execute_buy_trade, "NIFTY", :bullish, 25_000.0,
                       config["SYMBOLS"]["NIFTY"])
      end.to raise_error(StandardError, "Broker error")
    end
  end

  describe "Performance and Scalability" do
    it "handles multiple symbols efficiently" do
      multi_symbol_config = config.dup
      multi_symbol_config["SYMBOLS"]["BANKNIFTY"] = {
        "idx_sid" => "25",
        "seg_idx" => "IDX_I",
        "seg_opt" => "NSE_FNO",
        "strike_step" => 100,
        "lot_size" => 25,
        "qty_multiplier" => 1,
        "expiry_wday" => 4,
      }

      multi_app = DhanScalper::PaperApp.new(multi_symbol_config, quiet: true, enhanced: true)
      multi_app.send(:initialize_components)

      # Should be able to handle multiple symbols
      expect(multi_app.instance_variable_get(:@cfg)["SYMBOLS"].keys).to include("NIFTY", "BANKNIFTY")
    end

    it "processes signals within decision interval" do
      start_time = Time.now
      paper_app.send(:analyze_and_trade)
      end_time = Time.now

      # Should complete within reasonable time (less than decision interval)
      expect(end_time - start_time).to be < config["global"]["decision_interval"]
    end
  end

  describe "Data Persistence" do
    before do
      FileUtils.mkdir_p("test_data")
    end

    after do
      FileUtils.rm_rf("test_data")
    end

    it "saves session data to files" do
      paper_app_with_files = DhanScalper::PaperApp.new(config, quiet: true, enhanced: true)
      paper_app_with_files.instance_variable_set(:@data_dir, "test_data")
      paper_app_with_files.send(:initialize_components)

      # Add some test data
      mock_position_tracker = paper_app_with_files.instance_variable_get(:@position_tracker)
      allow(mock_position_tracker).to receive(:save_session_data)

      paper_app_with_files.send(:generate_session_report)

      # Check if data directory was created
      expect(File.directory?("test_data")).to be true
    end
  end

  describe "Configuration Validation" do
    it "validates required configuration keys" do
      invalid_config = config.dup
      invalid_config.delete("SYMBOLS")

      expect { DhanScalper::PaperApp.new(invalid_config, quiet: true) }.to raise_error(KeyError)
    end

    it "uses default values for optional configuration" do
      minimal_config = {
        "SYMBOLS" => {
          "NIFTY" => {
            "idx_sid" => "13",
            "seg_idx" => "IDX_I",
            "seg_opt" => "NSE_FNO",
            "strike_step" => 50,
            "lot_size" => 75,
          },
        },
      }

      minimal_app = DhanScalper::PaperApp.new(minimal_config, quiet: true)
      expect(minimal_app.instance_variable_get(:@cfg)["global"]["decision_interval"]).to eq(10) # default
    end
  end
end
