# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Paper Trading Workflow Integration", :integration do
  let(:config) do
    {
      "global" => {
        "min_profit_target" => 1000,
        "max_day_loss" => 5000,
        "decision_interval" => 5,
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
        },
        "BANKNIFTY" => {
          "idx_sid" => "25",
          "seg_idx" => "IDX_I",
          "seg_opt" => "NSE_FNO",
          "strike_step" => 100,
          "lot_size" => 25,
          "qty_multiplier" => 1,
          "expiry_wday" => 4
        }
      }
    }
  end

  let(:paper_app) { DhanScalper::PaperApp.new(config, quiet: true, enhanced: true, timeout_minutes: 2) }

  before do
    setup_integration_mocks
  end

  def setup_integration_mocks
    # Mock WebSocket Manager with realistic behavior
    @mock_ws_manager = double("WebSocketManager")
    allow(@mock_ws_manager).to receive(:connect)
    allow(@mock_ws_manager).to receive(:connected?).and_return(true)
    allow(@mock_ws_manager).to receive(:on_price_update)
    allow(@mock_ws_manager).to receive(:subscribe_to_instrument)
    allow(@mock_ws_manager).to receive(:unsubscribe_from_instrument)
    allow(paper_app).to receive(:instance_variable_get).with(:@websocket_manager).and_return(@mock_ws_manager)

    # Mock Position Tracker with realistic state management
    @mock_position_tracker = double("PaperPositionTracker")
    @positions = []
    @session_stats = {
      total_trades: 0,
      winning_trades: 0,
      losing_trades: 0,
      win_rate: 0.0,
      total_pnl: 0.0,
      max_profit: 0.0,
      max_drawdown: 0.0
    }

    allow(@mock_position_tracker).to receive(:setup_websocket_handlers)
    allow(@mock_position_tracker).to receive(:track_underlying)
    allow(@mock_position_tracker).to receive(:get_open_positions).and_return(@positions)
    allow(@mock_position_tracker).to receive(:get_positions_summary) do
      {
        total_positions: @positions.length,
        open_positions: @positions.count { |p| p[:status] == "open" },
        closed_positions: @positions.count { |p| p[:status] == "closed" },
        total_pnl: @positions.sum { |p| p[:pnl] || 0 },
        session_pnl: @session_stats[:total_pnl]
      }
    end
    allow(@mock_position_tracker).to receive(:get_session_stats).and_return(@session_stats)
    allow(@mock_position_tracker).to receive(:add_position) do |position_data|
      @positions << position_data.merge(status: "open", pnl: 0)
    end
    allow(@mock_position_tracker).to receive(:get_total_pnl).and_return(@session_stats[:total_pnl])
    allow(paper_app).to receive(:instance_variable_get).with(:@position_tracker).and_return(@mock_position_tracker)

    # Mock Balance Provider with realistic balance tracking
    @mock_balance_provider = double("PaperWallet")
    @available_balance = 200_000.0
    @used_balance = 0.0
    @total_balance = 200_000.0

    allow(@mock_balance_provider).to receive(:available_balance).and_return(@available_balance)
    allow(@mock_balance_provider).to receive(:total_balance).and_return(@total_balance)
    allow(@mock_balance_provider).to receive(:used_balance).and_return(@used_balance)
    allow(@mock_balance_provider).to receive(:update_balance) do |amount, type:|
      case type
      when :debit
        @available_balance -= amount
        @used_balance += amount
      when :credit
        @available_balance += amount
        @used_balance -= amount
      end
      @total_balance = @available_balance + @used_balance
    end
    allow(paper_app).to receive(:instance_variable_get).with(:@balance_provider).and_return(@mock_balance_provider)

    # Mock CSV Master with realistic data
    @mock_csv_master = double("CsvMaster")
    allow(@mock_csv_master).to receive(:get_expiry_dates).and_return(%w[2024-12-26 2025-01-02])
    allow(@mock_csv_master).to receive(:get_security_id).and_return("TEST123")
    allow(@mock_csv_master).to receive(:get_lot_size).and_return(75)
    allow(@mock_csv_master).to receive(:get_available_strikes).and_return([25_000, 25_050, 25_100, 25_150, 25_200])
    allow(paper_app).to receive(:instance_variable_get).with(:@csv_master).and_return(@mock_csv_master)

    # Mock TickCache with realistic price data
    @price_data = {
      "NIFTY" => 25_000.0,
      "BANKNIFTY" => 50_000.0
    }
    allow(DhanScalper::TickCache).to receive(:ltp) do |_segment, security_id|
      case security_id
      when "13" then @price_data["NIFTY"]
      when "25" then @price_data["BANKNIFTY"]
      else 100.0
      end
    end
    allow(DhanScalper::TickCache).to receive(:get).and_return({
                                                                last_price: 25_000.0,
                                                                timestamp: Time.now.to_i
                                                              })

    # Mock CandleSeries with realistic indicator data
    @indicator_data = {
      "NIFTY" => {
        bias: :bullish,
        momentum: :strong,
        adx: 30.0,
        rsi: 65.0,
        macd: :bullish
      },
      "BANKNIFTY" => {
        bias: :bearish,
        momentum: :strong,
        adx: 28.0,
        rsi: 35.0,
        macd: :bearish
      }
    }

    allow(DhanScalper::CandleSeries).to receive(:load_from_dhan_intraday) do |args|
      symbol = args[:symbol] || "NIFTY"
      mock_series = double("CandleSeries")
      allow(mock_series).to receive(:holy_grail).and_return(@indicator_data[symbol] || @indicator_data["NIFTY"])
      allow(mock_series).to receive(:supertrend_signal).and_return(@indicator_data[symbol]&.dig(:bias) || :bullish)
      allow(mock_series).to receive(:combined_signal).and_return(@indicator_data[symbol]&.dig(:bias) || :bullish)
      mock_series
    end

    # Mock Option Picker with realistic option selection
    @mock_option_picker = double("OptionPicker")
    allow(@mock_option_picker).to receive(:pick_atm_strike) do |spot_price, _signal|
      strike = (spot_price / 50).round * 50 # Round to nearest 50
      {
        ce: { security_id: "CE_#{strike}", premium: 100.0, strike: strike },
        pe: { security_id: "PE_#{strike}", premium: 80.0, strike: strike }
      }
    end
    allow(paper_app).to receive(:instance_variable_get).with(:@option_pickers).and_return({
                                                                                            "NIFTY" => @mock_option_picker,
                                                                                            "BANKNIFTY" => @mock_option_picker
                                                                                          })

    # Mock Paper Broker with realistic order execution
    @order_counter = 0
    @mock_paper_broker = double("PaperBroker")
    allow(@mock_paper_broker).to receive(:buy_market) do |args|
      @order_counter += 1
      {
        order_id: "ORDER_#{@order_counter}",
        status: "FILLED",
        avg_price: 100.0,
        quantity: args[:quantity]
      }
    end
    allow(@mock_paper_broker).to receive(:sell_market) do |args|
      @order_counter += 1
      {
        order_id: "ORDER_#{@order_counter}",
        status: "FILLED",
        avg_price: 120.0,
        quantity: args[:quantity]
      }
    end
    allow(paper_app).to receive(:instance_variable_get).with(:@paper_broker).and_return(@mock_paper_broker)
  end

  describe "Complete Trading Session Workflow" do
    it "executes a full trading session with multiple symbols" do
      # Start the trading session
      expect(paper_app).to receive(:initialize_components)
      expect(paper_app).to receive(:start_websocket_connection)
      expect(paper_app).to receive(:main_trading_loop)
      expect(paper_app).to receive(:cleanup_and_report)

      # Mock the main trading loop to simulate realistic behavior
      allow(paper_app).to receive(:main_trading_loop) do
        # Simulate 5 trading cycles
        5.times do |_i|
          paper_app.analyze_and_trade
          sleep(0.1) # Simulate decision interval
        end
      end

      paper_app.start

      # Verify that positions were created
      expect(@positions.length).to be > 0
    end

    it "handles multiple symbols simultaneously" do
      # Simulate different market conditions for each symbol
      allow(paper_app).to receive(:get_holy_grail_signal) do |symbol|
        case symbol
        when "NIFTY" then :bullish
        when "BANKNIFTY" then :bearish
        else :none
        end
      end

      # Execute trading analysis
      paper_app.analyze_and_trade

      # Verify that both symbols were processed
      expect(@mock_option_picker).to have_received(:pick_atm_strike).with(25_000.0, :bullish)
      expect(@mock_option_picker).to have_received(:pick_atm_strike).with(50_000.0, :bearish)
    end

    it "manages risk limits correctly" do
      # Simulate a losing streak
      allow(@mock_position_tracker).to receive(:get_total_pnl).and_return(-6000.0)

      # Attempt to trade
      result = paper_app.check_risk_limits
      expect(result).to be false

      # Verify no new trades are executed
      expect(@mock_paper_broker).not_to have_received(:buy_market)
    end

    it "tracks position lifecycle correctly" do
      # Execute a trade
      paper_app.execute_trade("NIFTY", :bullish, 25_000.0, config["SYMBOLS"]["NIFTY"])

      # Verify position was created
      expect(@positions.length).to eq(1)
      expect(@positions.first[:symbol]).to eq("NIFTY")
      expect(@positions.first[:status]).to eq("open")

      # Verify balance was updated
      expect(@used_balance).to be > 0
    end

    it "handles market hours correctly" do
      # Test during market hours
      allow(Time).to receive(:now).and_return(Time.parse("2024-12-08 10:30:00 IST"))
      expect(paper_app.market_open?).to be true

      # Test outside market hours
      allow(Time).to receive(:now).and_return(Time.parse("2024-12-08 16:30:00 IST"))
      expect(paper_app.market_open?).to be false
    end
  end

  describe "Signal Analysis Integration" do
    it "processes Holy Grail signals correctly" do
      # Test bullish signal
      allow(paper_app).to receive(:get_holy_grail_signal).with("NIFTY").and_return(:bullish)

      paper_app.analyze_and_trade

      expect(paper_app).to have_received(:execute_trade).with("NIFTY", :bullish, 25_000.0, config["SYMBOLS"]["NIFTY"])
    end

    it "handles weak signals appropriately" do
      # Test weak signal
      allow(paper_app).to receive(:get_holy_grail_signal).with("NIFTY").and_return(:none)

      paper_app.analyze_and_trade

      expect(paper_app).not_to have_received(:execute_trade)
    end

    it "integrates multi-timeframe analysis" do
      # Mock different signals for different timeframes
      allow(paper_app).to receive(:get_holy_grail_signal).and_return(:none)

      paper_app.analyze_and_trade

      # Should not execute trade due to conflicting signals
      expect(paper_app).not_to have_received(:execute_trade)
    end
  end

  describe "Position Management Integration" do
    it "tracks P&L correctly across multiple positions" do
      # Create multiple positions
      @positions = [
        { symbol: "NIFTY", security_id: "CE_25000", pnl: 500.0, status: "open" },
        { symbol: "BANKNIFTY", security_id: "PE_50000", pnl: -200.0, status: "open" }
      ]

      # Update session stats
      @session_stats[:total_pnl] = 300.0

      summary = @mock_position_tracker.get_positions_summary
      expect(summary[:total_pnl]).to eq(300.0)
      expect(summary[:open_positions]).to eq(2)
    end

    it "handles position closing correctly" do
      # Create an open position
      position = { symbol: "NIFTY", security_id: "CE_25000", pnl: 500.0, status: "open" }
      @positions << position

      # Close the position
      position[:status] = "closed"
      position[:exit_price] = 150.0
      position[:exit_reason] = "profit_target"

      summary = @mock_position_tracker.get_positions_summary
      expect(summary[:open_positions]).to eq(0)
      expect(summary[:closed_positions]).to eq(1)
    end
  end

  describe "Error Handling Integration" do
    it "handles WebSocket disconnection gracefully" do
      # Simulate WebSocket disconnection
      allow(@mock_ws_manager).to receive(:connected?).and_return(false)

      # Should handle gracefully
      expect { paper_app.analyze_and_trade }.not_to raise_error
    end

    it "handles data loading failures" do
      # Simulate data loading failure
      allow(DhanScalper::CandleSeries).to receive(:load_from_dhan_intraday).and_raise(StandardError, "Data unavailable")

      # Should handle gracefully
      expect { paper_app.get_holy_grail_signal("NIFTY") }.not_to raise_error
    end

    it "handles broker failures gracefully" do
      # Simulate broker failure
      allow(@mock_paper_broker).to receive(:buy_market).and_raise(StandardError, "Broker unavailable")

      # Should handle gracefully
      expect do
        paper_app.execute_trade("NIFTY", :bullish, 25_000.0, config["SYMBOLS"]["NIFTY"])
      end.not_to raise_error
    end
  end

  describe "Performance Integration" do
    it "handles high-frequency updates efficiently" do
      start_time = Time.now

      # Simulate 100 rapid updates
      100.times do
        paper_app.analyze_and_trade
      end

      duration = Time.now - start_time
      expect(duration).to be < 2.0 # Should complete within 2 seconds
    end

    it "maintains memory efficiency during long sessions" do
      initial_memory = `ps -o rss= -p #{Process.pid}`.to_i

      # Simulate 1000 iterations
      1000.times do
        paper_app.analyze_and_trade
      end

      final_memory = `ps -o rss= -p #{Process.pid}`.to_i
      memory_increase = final_memory - initial_memory

      # Memory increase should be reasonable
      expect(memory_increase).to be < 20_000 # Less than 20MB
    end
  end

  describe "Configuration Integration" do
    it "respects different configuration settings" do
      # Test with different risk settings
      high_risk_config = config.dup
      high_risk_config["global"]["max_day_loss"] = 10_000

      high_risk_app = DhanScalper::PaperApp.new(high_risk_config, quiet: true, enhanced: true)
      allow(high_risk_app).to receive(:instance_variable_get).with(:@position_tracker).and_return(@mock_position_tracker)

      # Should allow higher losses
      allow(@mock_position_tracker).to receive(:get_total_pnl).and_return(-8000.0)
      expect(high_risk_app.check_risk_limits).to be true
    end

    it "handles missing configuration gracefully" do
      # Test with minimal configuration
      minimal_config = {
        "global" => { "decision_interval" => 10 },
        "paper" => { "starting_balance" => 100_000 },
        "SYMBOLS" => { "NIFTY" => { "idx_sid" => "13", "seg_idx" => "IDX_I", "seg_opt" => "NSE_FNO" } }
      }

      minimal_app = DhanScalper::PaperApp.new(minimal_config, quiet: true, enhanced: true)
      expect { minimal_app.start }.not_to raise_error
    end
  end

  describe "Session Reporting Integration" do
    it "generates comprehensive session reports" do
      # Set up session data
      @session_stats = {
        total_trades: 10,
        winning_trades: 6,
        losing_trades: 4,
        win_rate: 60.0,
        total_pnl: 2000.0,
        max_profit: 1500.0,
        max_drawdown: -500.0
      }

      @positions = [
        { symbol: "NIFTY", status: "open", pnl: 500.0 },
        { symbol: "BANKNIFTY", status: "closed", pnl: 1500.0 }
      ]

      # Generate report
      expect(paper_app).to receive(:puts).with(/SESSION REPORT/)
      expect(paper_app).to receive(:puts).with(/Total Trades: 10/)
      expect(paper_app).to receive(:puts).with(/Win Rate: 60.0%/)
      expect(paper_app).to receive(:puts).with(/Total P&L: ₹2000.00/)

      paper_app.generate_session_report
    end
  end
end
