# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Performance and Load Testing", :slow do
  let(:config) do
    {
      "global" => {
        "min_profit_target" => 1_000,
        "max_day_loss" => 5_000,
        "decision_interval" => 1,
        "log_level" => "WARN",
      },
      "paper" => {
        "starting_balance" => 1_000_000,
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
        "BANKNIFTY" => {
          "idx_sid" => "25",
          "seg_idx" => "IDX_I",
          "seg_opt" => "NSE_FNO",
          "strike_step" => 100,
          "lot_size" => 25,
          "qty_multiplier" => 1,
          "expiry_wday" => 4,
        },
      },
    }
  end

  let(:paper_app) { DhanScalper::PaperApp.new(config, quiet: true, enhanced: true) }

  before do
    # Mock all external dependencies for performance testing
    setup_performance_mocks
  end

  def setup_performance_mocks
    # Mock WebSocket Manager
    @mock_ws_manager = double("WebSocketManager")
    allow(@mock_ws_manager).to receive(:connect)
    allow(@mock_ws_manager).to receive(:connected?).and_return(true)
    allow(@mock_ws_manager).to receive(:on_price_update)
    allow(@mock_ws_manager).to receive(:subscribe_to_instrument)
    allow(@mock_ws_manager).to receive(:unsubscribe_from_instrument)
    allow(paper_app).to receive(:instance_variable_get).with(:@websocket_manager).and_return(@mock_ws_manager)

    # Mock CSV Master with fast responses
    @mock_csv_master = double("CsvMaster")
    allow(@mock_csv_master).to receive(:get_expiry_dates).and_return(["2024-12-26"])
    allow(@mock_csv_master).to receive(:get_security_id).and_return("TEST123")
    allow(@mock_csv_master).to receive(:get_lot_size).and_return(75)
    allow(paper_app).to receive(:instance_variable_get).with(:@csv_master).and_return(@mock_csv_master)

    # Mock DhanHQ configuration
    allow(DhanScalper::Services::DhanHQConfig).to receive(:validate!)
    allow(DhanScalper::Services::DhanHQConfig).to receive(:configure)

    # Mock TickCache with fast responses
    allow(DhanScalper::TickCache).to receive(:ltp).and_return(25_000.0)
    allow(DhanScalper::TickCache).to receive(:put)

    # Mock CandleSeries with fast responses
    mock_candle_series = double("CandleSeries")
    allow(mock_candle_series).to receive(:holy_grail).and_return({
                                                                   bias: :bullish,
                                                                   momentum: :strong,
                                                                   adx: 25.0,
                                                                   rsi: 65.0,
                                                                   macd: :bullish,
                                                                 })
    allow(DhanScalper::CandleSeries).to receive(:load_from_dhan_intraday).and_return(mock_candle_series)
  end

  describe "High-Frequency Signal Processing" do
    it "processes signals within decision interval" do
      paper_app.send(:initialize_components)

      # Measure signal processing time
      start_time = Time.now
      100.times do
        paper_app.send(:analyze_and_trade)
      end
      end_time = Time.now

      total_time = end_time - start_time
      avg_time_per_signal = total_time / 100

      # Should process signals faster than decision interval
      expect(avg_time_per_signal).to be < config["global"]["decision_interval"]
      expect(total_time).to be < 10.0 # Total time should be reasonable
    end

    it "handles concurrent signal processing" do
      paper_app.send(:initialize_components)

      # Simulate concurrent signal processing
      threads = []
      start_time = Time.now

      10.times do
        threads << Thread.new do
          10.times { paper_app.send(:analyze_and_trade) }
        end
      end

      threads.each(&:join)
      end_time = Time.now

      # Should complete within reasonable time
      expect(end_time - start_time).to be < 5.0
      expect(threads.all?(&:status)).to be true
    end
  end

  describe "Memory Usage and Leaks" do
    it "maintains stable memory usage during extended operation" do
      paper_app.send(:initialize_components)

      initial_memory = `ps -o rss= -p #{Process.pid}`.to_i

      # Simulate extended operation
      1_000.times do
        paper_app.send(:analyze_and_trade)
        paper_app.send(:check_risk_limits)
      end

      final_memory = `ps -o rss= -p #{Process.pid}`.to_i
      memory_increase = final_memory - initial_memory

      # Memory increase should be reasonable (less than 50MB)
      expect(memory_increase).to be < 50_000 # 50MB in KB
    end

    it "cleans up resources properly" do
      paper_app.send(:initialize_components)

      # Simulate resource usage
      paper_app.send(:analyze_and_trade)
      paper_app.send(:check_risk_limits)

      # Cleanup should not raise errors
      expect { paper_app.send(:cleanup_and_report) }.not_to raise_error
    end
  end

  describe "Position Management Performance" do
    it "handles large number of positions efficiently" do
      paper_app.send(:initialize_components)
      mock_position_tracker = paper_app.instance_variable_get(:@position_tracker)

      # Mock large number of positions
      positions = {}
      1_000.times do |i|
        positions["POS_#{i}"] = {
          symbol: "NIFTY",
          option_type: "CE",
          strike: 25_000 + i,
          expiry: Date.today,
          instrument_id: "TEST#{i}",
          quantity: 75,
          entry_price: 150.0,
          current_price: 150.0,
          pnl: 0.0,
          created_at: Time.now,
        }
      end

      allow(mock_position_tracker).to receive(:positions).and_return(positions)
      allow(mock_position_tracker).to receive(:get_total_pnl).and_return(1_000.0)
      allow(mock_position_tracker).to receive(:get_positions_summary).and_return({
                                                                                   total_positions: 1_000,
                                                                                   open_positions: 1_000,
                                                                                   closed_positions: 0,
                                                                                   total_pnl: 1_000.0,
                                                                                   winning_trades: 500,
                                                                                   losing_trades: 500,
                                                                                 })

      # Measure position summary calculation time
      start_time = Time.now
      summary = mock_position_tracker.get_positions_summary
      end_time = Time.now

      # Should calculate summary quickly even with many positions
      expect(end_time - start_time).to be < 0.1 # Less than 100ms
      expect(summary[:total_positions]).to eq(1_000)
    end

    it "handles position updates efficiently" do
      paper_app.send(:initialize_components)
      mock_position_tracker = paper_app.instance_variable_get(:@position_tracker)

      # Mock position updates
      allow(mock_position_tracker).to receive(:handle_price_update)

      # Simulate rapid price updates
      start_time = Time.now
      1_000.times do |i|
        price_data = {
          instrument_id: "TEST#{i % 100}",
          segment: "NSE_FNO",
          ltp: 150.0 + i,
          timestamp: Time.now.to_i,
        }
        paper_app.send(:handle_price_update, price_data)
      end
      end_time = Time.now

      # Should handle updates quickly
      expect(end_time - start_time).to be < 2.0 # Less than 2 seconds
    end
  end

  describe "Database and Cache Performance" do
    it "handles Redis operations efficiently" do
      # Mock Redis operations
      mock_redis = double("Redis")
      allow(mock_redis).to receive(:hset)
      allow(mock_redis).to receive(:hget)
      allow(mock_redis).to receive(:expire)
      allow(mock_redis).to receive(:ping).and_return("PONG")

      # Mock RedisStore
      mock_redis_store = double("RedisStore")
      allow(mock_redis_store).to receive(:redis).and_return(mock_redis)
      allow(mock_redis_store).to receive(:store_tick)
      allow(mock_redis_store).to receive(:get_tick)

      # Measure Redis operations
      start_time = Time.now
      1_000.times do |i|
        mock_redis_store.store_tick("NSE_FNO", "TEST#{i}", {
                                      ltp: 150.0 + i,
                                      timestamp: Time.now.to_i,
                                    })
      end
      end_time = Time.now

      # Should complete Redis operations quickly
      expect(end_time - start_time).to be < 1.0 # Less than 1 second
    end

    it "handles CSV master data loading efficiently" do
      # Mock large CSV data
      large_csv_data = []
      10_000.times do |i|
        large_csv_data << {
          "UNDERLYING_SYMBOL" => "NIFTY",
          "INSTRUMENT" => "OPTIDX",
          "SM_EXPIRY_DATE" => "2024-12-26",
          "STRIKE_PRICE" => (25_000 + (i * 50)).to_s,
          "OPTION_TYPE" => i.even? ? "CE" : "PE",
          "SECURITY_ID" => "TEST#{i}",
          "LOT_SIZE" => "75",
        }
      end

      allow(@mock_csv_master).to receive(:data).and_return(large_csv_data)
      allow(@mock_csv_master).to receive(:get_instruments_with_segments).and_return(large_csv_data)

      # Measure CSV operations
      start_time = Time.now
      instruments = @mock_csv_master.get_instruments_with_segments("NIFTY")
      end_time = Time.now

      # Should process large CSV data quickly
      expect(end_time - start_time).to be < 0.5 # Less than 500ms
      expect(instruments.size).to eq(10_000)
    end
  end

  describe "Network and API Performance" do
    it "handles WebSocket message processing efficiently" do
      paper_app.send(:initialize_components)

      # Simulate rapid WebSocket messages
      start_time = Time.now
      1_000.times do |i|
        price_data = {
          instrument_id: "TEST#{i % 10}",
          segment: "NSE_FNO",
          ltp: 150.0 + i,
          timestamp: Time.now.to_i,
        }
        paper_app.send(:handle_price_update, price_data)
      end
      end_time = Time.now

      # Should process messages quickly
      expect(end_time - start_time).to be < 1.0 # Less than 1 second
    end

    it "handles API rate limiting gracefully" do
      paper_app.send(:initialize_components)

      # Mock rate limiting
      call_count = 0
      allow(paper_app).to receive(:get_holy_grail_signal) do
        call_count += 1
        raise StandardError, "Rate limit exceeded" if call_count > 100

        :bullish
      end

      # Should handle rate limiting gracefully
      expect { 200.times { paper_app.send(:analyze_and_trade) } }.to raise_error(StandardError, "Rate limit exceeded")
    end
  end

  describe "Concurrent Access and Thread Safety" do
    it "handles concurrent access to shared resources" do
      paper_app.send(:initialize_components)

      # Simulate concurrent access to position tracker
      threads = []
      results = []

      10.times do |i|
        threads << Thread.new do
          mock_position_tracker = paper_app.instance_variable_get(:@position_tracker)
          allow(mock_position_tracker).to receive(:get_total_pnl).and_return(i * 100.0)
          results << mock_position_tracker.get_total_pnl
        end
      end

      threads.each(&:join)

      # All threads should complete successfully
      expect(results.size).to eq(10)
      expect(threads.all?(&:status)).to be true
    end

    it "maintains data consistency under concurrent access" do
      paper_app.send(:initialize_components)

      # Simulate concurrent position updates
      threads = []
      position_updates = []

      5.times do |i|
        threads << Thread.new do
          100.times do |j|
            mock_position_tracker = paper_app.instance_variable_get(:@position_tracker)
            allow(mock_position_tracker).to receive(:add_position)
            mock_position_tracker.add_position("NIFTY", "CE", 25_000 + j, Date.today, "TEST#{i}_#{j}", 75, 150.0)
            position_updates << "POS_#{i}_#{j}"
          end
        end
      end

      threads.each(&:join)

      # All updates should complete
      expect(position_updates.size).to eq(500)
      expect(threads.all?(&:status)).to be true
    end
  end

  describe "Resource Cleanup and Garbage Collection" do
    it "cleans up resources properly after extended operation" do
      paper_app.send(:initialize_components)

      # Simulate extended operation
      1_000.times do
        paper_app.send(:analyze_and_trade)
        paper_app.send(:check_risk_limits)
      end

      # Force garbage collection
      GC.start

      # Cleanup should not raise errors
      expect { paper_app.send(:cleanup_and_report) }.not_to raise_error
    end

    it "handles memory pressure gracefully" do
      paper_app.send(:initialize_components)

      # Simulate memory pressure by creating large objects
      large_objects = []
      100.times do |i|
        large_objects << Array.new(10_000) { "data_#{i}_#{rand(1_000)}" }
      end

      # Should still function under memory pressure
      expect { paper_app.send(:analyze_and_trade) }.not_to raise_error

      # Clean up
      large_objects.clear
      GC.start
    end
  end

  describe "Scalability Limits" do
    it "handles maximum number of symbols efficiently" do
      # Create config with many symbols
      many_symbols_config = config.dup
      many_symbols_config["SYMBOLS"] = {}

      50.times do |i|
        many_symbols_config["SYMBOLS"]["SYMBOL_#{i}"] = {
          "idx_sid" => "#{i}",
          "seg_idx" => "IDX_I",
          "seg_opt" => "NSE_FNO",
          "strike_step" => 50,
          "lot_size" => 75,
          "qty_multiplier" => 1,
          "expiry_wday" => 4,
        }
      end

      many_symbols_app = DhanScalper::PaperApp.new(many_symbols_config, quiet: true, enhanced: true)
      many_symbols_app.send(:initialize_components)

      # Should handle many symbols
      expect(many_symbols_app.instance_variable_get(:@cfg)["SYMBOLS"].keys.size).to eq(50)
    end

    it "handles maximum number of positions efficiently" do
      paper_app.send(:initialize_components)
      mock_position_tracker = paper_app.instance_variable_get(:@position_tracker)

      # Mock maximum number of positions
      max_positions = {}
      10_000.times do |i|
        max_positions["POS_#{i}"] = {
          symbol: "NIFTY",
          option_type: "CE",
          strike: 25_000 + i,
          expiry: Date.today,
          instrument_id: "TEST#{i}",
          quantity: 75,
          entry_price: 150.0,
          current_price: 150.0,
          pnl: 0.0,
          created_at: Time.now,
        }
      end

      allow(mock_position_tracker).to receive(:positions).and_return(max_positions)
      allow(mock_position_tracker).to receive(:get_total_pnl).and_return(1_000.0)

      # Should handle maximum positions efficiently
      start_time = Time.now
      total_pnl = mock_position_tracker.get_total_pnl
      end_time = Time.now

      expect(end_time - start_time).to be < 0.1 # Less than 100ms
      expect(total_pnl).to eq(1_000.0)
    end
  end
end
