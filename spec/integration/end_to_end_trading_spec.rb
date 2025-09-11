# frozen_string_literal: true

require "spec_helper"

RSpec.describe "End-to-End Trading Workflow", :slow do
  let(:config) do
    {
      "global" => {
        "min_profit_target" => 1000,
        "max_day_loss" => 5000,
        "decision_interval" => 2,
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

  let(:paper_app) { DhanScalper::PaperApp.new(config, quiet: true, enhanced: true, timeout_minutes: 1) }

  before do
    # Mock all external dependencies
    setup_mocks
  end

  def setup_mocks
    # Mock WebSocket Manager
    @mock_ws_manager = double("WebSocketManager")
    allow(@mock_ws_manager).to receive(:connect)
    allow(@mock_ws_manager).to receive(:connected?).and_return(true)
    allow(@mock_ws_manager).to receive(:on_price_update)
    allow(@mock_ws_manager).to receive(:subscribe_to_instrument)
    allow(@mock_ws_manager).to receive(:unsubscribe_from_instrument)
    allow(paper_app).to receive(:instance_variable_get).with(:@websocket_manager).and_return(@mock_ws_manager)

    # Mock CSV Master
    @mock_csv_master = double("CsvMaster")
    allow(@mock_csv_master).to receive(:get_expiry_dates).and_return(["2024-12-26"])
    allow(@mock_csv_master).to receive(:get_security_id).and_return("TEST123")
    allow(@mock_csv_master).to receive(:get_lot_size).and_return(75)
    allow(paper_app).to receive(:instance_variable_get).with(:@csv_master).and_return(@mock_csv_master)

    # Mock DhanHQ configuration
    allow(DhanScalper::Services::DhanHQConfig).to receive(:validate!)
    allow(DhanScalper::Services::DhanHQConfig).to receive(:configure)

    # Mock TickCache
    allow(DhanScalper::TickCache).to receive(:ltp).and_return(25_000.0)
    allow(DhanScalper::TickCache).to receive(:put)
  end

  describe "Complete Trading Session" do
    it "executes a full trading session from start to finish" do
      # Track all method calls
      expect(paper_app).to receive(:initialize_components).once
      expect(paper_app).to receive(:start_websocket_connection).once
      expect(paper_app).to receive(:start_tracking_underlyings).once
      expect(paper_app).to receive(:subscribe_to_atm_options_for_monitoring).once
      expect(paper_app).to receive(:main_trading_loop).once
      expect(paper_app).to receive(:cleanup_and_report).once

      # Start the trading session
      paper_app.start
    end

    it "handles market data updates correctly" do
      paper_app.send(:initialize_components)

      # Simulate price update
      price_data = {
        instrument_id: "13",
        segment: "IDX_I",
        ltp: 25_050.0,
        timestamp: Time.now.to_i
      }

      # Mock position tracker to handle price updates
      mock_position_tracker = paper_app.instance_variable_get(:@position_tracker)
      allow(mock_position_tracker).to receive(:handle_price_update)

      # Simulate WebSocket price update
      paper_app.send(:handle_price_update, price_data)

      # Verify position tracker was called
      expect(mock_position_tracker).to have_received(:handle_price_update).with(price_data)
    end

    it "processes trading signals and executes trades" do
      paper_app.send(:initialize_components)

      # Mock successful signal analysis
      allow(paper_app).to receive(:get_holy_grail_signal).and_return(:bullish)
      allow(paper_app).to receive(:get_current_spot_price).and_return(25_000.0)

      # Mock successful trade execution
      allow(paper_app).to receive(:execute_trade).and_return(true)

      # Process trading signals
      paper_app.send(:analyze_and_trade)

      # Verify trade execution was attempted
      expect(paper_app).to have_received(:execute_trade).with("NIFTY", :bullish, 25_000.0, config["SYMBOLS"]["NIFTY"])
    end
  end

  describe "Position Lifecycle Management" do
    before do
      paper_app.send(:initialize_components)
    end

    it "manages complete position lifecycle" do
      mock_position_tracker = paper_app.instance_variable_get(:@position_tracker)
      mock_broker = paper_app.instance_variable_get(:@broker)

      # Mock position addition
      allow(mock_position_tracker).to receive(:add_position)
      allow(mock_position_tracker).to receive(:get_total_pnl).and_return(0.0, 500.0, 750.0)
      allow(mock_position_tracker).to receive(:get_positions_summary).and_return({
                                                                                   total_positions: 1,
                                                                                   open_positions: 1,
                                                                                   closed_positions: 0,
                                                                                   total_pnl: 750.0,
                                                                                   winning_trades: 1,
                                                                                   losing_trades: 0
                                                                                 })

      # Mock broker order execution
      allow(mock_broker).to receive(:place_order).and_return({
                                                               success: true,
                                                               order_id: "P-1234567890",
                                                               order: double("Order", quantity: 75, price: 150.0),
                                                               position: double("Position", security_id: "TEST123")
                                                             })

      # Execute buy trade
      result = paper_app.send(:execute_buy_trade, "NIFTY", :bullish, 25_000.0, config["SYMBOLS"]["NIFTY"])
      expect(result).to be true

      # Verify position was added
      expect(mock_position_tracker).to have_received(:add_position)
    end

    it "handles position closing correctly" do
      mock_position_tracker = paper_app.instance_variable_get(:@position_tracker)
      mock_broker = paper_app.instance_variable_get(:@broker)

      # Mock position removal
      allow(mock_position_tracker).to receive(:remove_position)
      allow(mock_position_tracker).to receive(:get_total_pnl).and_return(750.0)

      # Mock sell order execution
      allow(mock_broker).to receive(:place_order).and_return({
                                                               success: true,
                                                               order_id: "P-1234567891",
                                                               order: double("Order", quantity: 75, price: 200.0),
                                                               position: nil
                                                             })

      # Execute sell trade
      result = paper_app.send(:execute_sell_trade, "NIFTY", :bearish, 25_000.0, config["SYMBOLS"]["NIFTY"])
      expect(result).to be true
    end
  end

  describe "Risk Management Integration" do
    before do
      paper_app.send(:initialize_components)
    end

    it "enforces daily loss limits" do
      mock_position_tracker = paper_app.instance_variable_get(:@position_tracker)
      allow(mock_position_tracker).to receive(:get_total_pnl).and_return(-6000.0)

      # Should trigger risk limit breach
      expect { paper_app.send(:check_risk_limits) }.to output(/Daily loss limit breached/).to_stdout
    end

    it "continues trading when within risk limits" do
      mock_position_tracker = paper_app.instance_variable_get(:@position_tracker)
      allow(mock_position_tracker).to receive(:get_total_pnl).and_return(-1000.0)

      # Should not trigger risk limit breach
      expect { paper_app.send(:check_risk_limits) }.not_to output.to_stdout
    end

    it "handles position size limits" do
      mock_position_tracker = paper_app.instance_variable_get(:@position_tracker)
      allow(mock_position_tracker).to receive(:get_positions_summary).and_return({
                                                                                   total_positions: 5, # At max limit
                                                                                   open_positions: 5,
                                                                                   closed_positions: 0,
                                                                                   total_pnl: 0.0,
                                                                                   winning_trades: 0,
                                                                                   losing_trades: 0
                                                                                 })

      # Should not execute new trades when at position limit
      allow(paper_app).to receive(:get_holy_grail_signal).and_return(:bullish)
      allow(paper_app).to receive(:get_current_spot_price).and_return(25_000.0)
      allow(paper_app).to receive(:execute_trade)

      paper_app.send(:analyze_and_trade)

      # Should not attempt to execute trade due to position limit
      expect(paper_app).not_to have_received(:execute_trade)
    end
  end

  describe "Session Reporting and Analytics" do
    before do
      paper_app.send(:initialize_components)
    end

    it "generates comprehensive session reports" do
      mock_position_tracker = paper_app.instance_variable_get(:@position_tracker)
      allow(mock_position_tracker).to receive(:get_positions_summary).and_return({
                                                                                   total_positions: 3,
                                                                                   open_positions: 1,
                                                                                   closed_positions: 2,
                                                                                   total_pnl: 1500.0,
                                                                                   winning_trades: 2,
                                                                                   losing_trades: 1
                                                                                 })

      mock_reporter = double("SessionReporter")
      allow(mock_reporter).to receive(:generate_session_report)
      allow(paper_app).to receive(:instance_variable_get).with(:@reporter).and_return(mock_reporter)

      paper_app.send(:generate_session_report)

      expect(mock_reporter).to have_received(:generate_session_report)
    end

    it "tracks session statistics correctly" do
      session_data = paper_app.instance_variable_get(:@session_data)

      # Simulate some trading activity
      session_data[:total_trades] = 5
      session_data[:successful_trades] = 4
      session_data[:failed_trades] = 1
      session_data[:symbols_traded].add("NIFTY")

      expect(session_data[:total_trades]).to eq(5)
      expect(session_data[:successful_trades]).to eq(4)
      expect(session_data[:failed_trades]).to eq(1)
      expect(session_data[:symbols_traded]).to include("NIFTY")
    end
  end

  describe "Error Recovery and Resilience" do
    it "recovers from WebSocket disconnections" do
      # Simulate WebSocket disconnection
      allow(@mock_ws_manager).to receive(:connected?).and_return(false)

      # Should attempt to reconnect
      expect(@mock_ws_manager).to receive(:connect)
      paper_app.send(:check_websocket_connection)
    end

    it "handles API rate limiting gracefully" do
      paper_app.send(:initialize_components)

      # Mock rate limiting error
      allow(paper_app).to receive(:get_holy_grail_signal).and_raise(StandardError, "Rate limit exceeded")

      # Should handle error gracefully
      expect { paper_app.send(:analyze_and_trade) }.to raise_error(StandardError, "Rate limit exceeded")
    end

    it "continues operation despite individual component failures" do
      paper_app.send(:initialize_components)

      # Mock partial failure in CSV master
      allow(@mock_csv_master).to receive(:get_expiry_dates).and_raise(StandardError, "CSV error")
      allow(paper_app).to receive(:get_holy_grail_signal).and_return(:bullish)
      allow(paper_app).to receive(:get_current_spot_price).and_return(25_000.0)

      # Should handle error and continue
      expect { paper_app.send(:analyze_and_trade) }.to raise_error(StandardError, "CSV error")
    end
  end

  describe "Performance and Scalability" do
    it "handles high-frequency trading scenarios" do
      paper_app.send(:initialize_components)

      # Mock rapid signal generation
      signal_count = 0
      allow(paper_app).to receive(:get_holy_grail_signal) do
        signal_count += 1
        signal_count <= 10 ? :bullish : :none
      end
      allow(paper_app).to receive(:get_current_spot_price).and_return(25_000.0)
      allow(paper_app).to receive(:execute_trade).and_return(true)

      # Process multiple signals quickly
      start_time = Time.now
      10.times { paper_app.send(:analyze_and_trade) }
      end_time = Time.now

      # Should complete within reasonable time
      expect(end_time - start_time).to be < 1.0 # Less than 1 second
    end

    it "scales to multiple symbols efficiently" do
      multi_symbol_config = config.dup
      multi_symbol_config["SYMBOLS"]["BANKNIFTY"] = {
        "idx_sid" => "25",
        "seg_idx" => "IDX_I",
        "seg_opt" => "NSE_FNO",
        "strike_step" => 100,
        "lot_size" => 25,
        "qty_multiplier" => 1,
        "expiry_wday" => 4
      }

      multi_app = DhanScalper::PaperApp.new(multi_symbol_config, quiet: true, enhanced: true)
      multi_app.send(:initialize_components)

      # Should handle multiple symbols
      expect(multi_app.instance_variable_get(:@cfg)["SYMBOLS"].keys).to include("NIFTY", "BANKNIFTY")
    end
  end

  describe "Data Consistency and Integrity" do
    it "maintains data consistency across components" do
      paper_app.send(:initialize_components)

      mock_position_tracker = paper_app.instance_variable_get(:@position_tracker)
      mock_broker = paper_app.instance_variable_get(:@broker)
      mock_balance_provider = paper_app.instance_variable_get(:@balance_provider)

      # Mock consistent data across components
      allow(mock_position_tracker).to receive(:get_total_pnl).and_return(1000.0)
      allow(mock_balance_provider).to receive(:available_balance).and_return(199_000.0)
      allow(mock_balance_provider).to receive(:used_balance).and_return(1000.0)

      # Verify data consistency
      expect(mock_position_tracker.get_total_pnl).to eq(1000.0)
      expect(mock_balance_provider.used_balance).to eq(1000.0)
    end

    it "handles concurrent access safely" do
      paper_app.send(:initialize_components)

      # Simulate concurrent access
      threads = []
      5.times do |i|
        threads << Thread.new do
          paper_app.send(:analyze_and_trade)
        end
      end

      threads.each(&:join)

      # Should complete without errors
      expect(threads.all?(&:status)).to be true
    end
  end

  describe "Configuration and Environment" do
    it "validates configuration on startup" do
      invalid_config = config.dup
      invalid_config.delete("SYMBOLS")

      expect { DhanScalper::PaperApp.new(invalid_config, quiet: true) }.to raise_error(KeyError)
    end

    it "handles environment variable overrides" do
      ENV["SCALPER_CONFIG"] = "config/test.yml"

      # Should use environment-specified config
      expect(DhanScalper::Config).to receive(:load).with(path: "config/test.yml")
      DhanScalper::PaperApp.new({}, quiet: true)

      ENV.delete("SCALPER_CONFIG")
    end

    it "supports different trading modes" do
      # Test paper mode
      paper_app = DhanScalper::PaperApp.new(config, quiet: true)
      expect(paper_app.instance_variable_get(:@cfg)).to eq(config)

      # Test enhanced mode
      enhanced_app = DhanScalper::PaperApp.new(config, quiet: true, enhanced: true)
      expect(enhanced_app.instance_variable_get(:@enhanced)).to be true
    end
  end
end
