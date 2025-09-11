# frozen_string_literal: true

module TestHelpers
  # Helper methods for setting up test environments
  def setup_paper_trading_mocks
    # Mock WebSocket Manager
    mock_ws_manager = double("WebSocketManager")
    allow(mock_ws_manager).to receive(:connect)
    allow(mock_ws_manager).to receive(:connected?).and_return(true)
    allow(mock_ws_manager).to receive(:on_price_update)
    allow(mock_ws_manager).to receive(:subscribe_to_instrument)
    allow(mock_ws_manager).to receive(:unsubscribe_from_instrument)
    mock_ws_manager
  end

  def setup_csv_master_mocks
    # Mock CSV Master
    mock_csv_master = double("CsvMaster")
    allow(mock_csv_master).to receive(:get_expiry_dates).and_return(["2024-12-26"])
    allow(mock_csv_master).to receive(:get_security_id).and_return("TEST123")
    allow(mock_csv_master).to receive(:get_lot_size).and_return(75)
    allow(mock_csv_master).to receive(:get_instruments_with_segments).and_return([])
    mock_csv_master
  end

  def setup_broker_mocks
    # Mock Paper Broker
    mock_broker = double("PaperBroker")
    allow(mock_broker).to receive(:place_order).and_return({
                                                             success: true,
                                                             order_id: "P-1234567890",
                                                             order: double("Order", quantity: 75, price: 150.0),
                                                             position: double("Position", security_id: "TEST123")
                                                           })
    mock_broker
  end

  def setup_position_tracker_mocks
    # Mock Position Tracker
    mock_position_tracker = double("PaperPositionTracker")
    allow(mock_position_tracker).to receive(:setup_websocket_handlers)
    allow(mock_position_tracker).to receive(:add_position)
    allow(mock_position_tracker).to receive(:remove_position)
    allow(mock_position_tracker).to receive(:get_total_pnl).and_return(0.0)
    allow(mock_position_tracker).to receive(:get_positions_summary).and_return({
                                                                                 total_positions: 0,
                                                                                 open_positions: 0,
                                                                                 closed_positions: 0,
                                                                                 total_pnl: 0.0,
                                                                                 winning_trades: 0,
                                                                                 losing_trades: 0
                                                                               })
    allow(mock_position_tracker).to receive(:get_underlying_price).and_return(25_000.0)
    allow(mock_position_tracker).to receive(:handle_price_update)
    mock_position_tracker
  end

  def setup_balance_provider_mocks
    # Mock Balance Provider
    mock_balance_provider = double("PaperWallet")
    allow(mock_balance_provider).to receive(:available_balance).and_return(200_000.0)
    allow(mock_balance_provider).to receive(:used_balance).and_return(0.0)
    allow(mock_balance_provider).to receive(:total_balance).and_return(200_000.0)
    allow(mock_balance_provider).to receive(:update_balance)
    allow(mock_balance_provider).to receive(:add_realized_pnl)
    mock_balance_provider
  end

  def setup_tick_cache_mocks
    # Mock TickCache
    allow(DhanScalper::TickCache).to receive(:ltp).and_return(25_000.0)
    allow(DhanScalper::TickCache).to receive(:put)
    allow(DhanScalper::TickCache).to receive(:get).and_return(TestData::SAMPLE_TICK_DATA)
    allow(DhanScalper::TickCache).to receive(:fresh?).and_return(true)
  end

  def setup_candle_series_mocks
    # Mock CandleSeries
    mock_candle_series = double("CandleSeries")
    allow(mock_candle_series).to receive(:holy_grail).and_return(TestData::SAMPLE_HOLY_GRAIL_SIGNAL)
    allow(mock_candle_series).to receive(:supertrend_signal).and_return(:bullish)
    allow(mock_candle_series).to receive(:candles).and_return(TestData::SAMPLE_CANDLES)
    allow(mock_candle_series).to receive(:to_hash).and_return({
                                                                timestamps: TestData::SAMPLE_CANDLES.map do |c|
                                                                  c[:timestamp]
                                                                end,
                                                                opens: TestData::SAMPLE_CANDLES.map { |c| c[:open] },
                                                                highs: TestData::SAMPLE_CANDLES.map { |c| c[:high] },
                                                                lows: TestData::SAMPLE_CANDLES.map { |c| c[:low] },
                                                                closes: TestData::SAMPLE_CANDLES.map { |c| c[:close] },
                                                                volumes: TestData::SAMPLE_CANDLES.map { |c| c[:volume] }
                                                              })
    allow(DhanScalper::CandleSeries).to receive(:load_from_dhan_intraday).and_return(mock_candle_series)
  end

  def setup_dhanhq_mocks
    # Mock DhanHQ configuration
    allow(DhanScalper::Services::DhanHQConfig).to receive(:validate!)
    allow(DhanScalper::Services::DhanHQConfig).to receive(:configure)
    allow(DhanScalper::Services::DhanHQConfig).to receive(:configured?).and_return(true)
    allow(DhanScalper::Services::DhanHQConfig).to receive(:status).and_return({
                                                                                configured: true,
                                                                                client_id: "TEST_CLIENT_ID",
                                                                                access_token: "TEST_ACCESS_TOKEN"
                                                                              })
  end

  def setup_redis_mocks
    # Mock Redis
    mock_redis = double("Redis")
    allow(mock_redis).to receive(:hset)
    allow(mock_redis).to receive(:hget)
    allow(mock_redis).to receive(:expire)
    allow(mock_redis).to receive(:ping).and_return("PONG")
    allow(mock_redis).to receive(:close)
    allow(mock_redis).to receive(:disconnect)

    # Mock RedisStore
    mock_redis_store = double("RedisStore")
    allow(mock_redis_store).to receive(:redis).and_return(mock_redis)
    allow(mock_redis_store).to receive(:store_tick)
    allow(mock_redis_store).to receive(:get_tick)
    allow(mock_redis_store).to receive(:connect)
    allow(mock_redis_store).to receive(:disconnect)
    mock_redis_store
  end

  # Helper methods for creating test scenarios
  def create_bullish_market_scenario
    {
      spot_price: 25_000.0,
      holy_grail_signal: :bullish,
      trend_analysis: :bullish,
      option_premium: 150.0,
      expected_trade: :buy_ce
    }
  end

  def create_bearish_market_scenario
    {
      spot_price: 25_000.0,
      holy_grail_signal: :bearish,
      trend_analysis: :bearish,
      option_premium: 120.0,
      expected_trade: :buy_pe
    }
  end

  def create_sideways_market_scenario
    {
      spot_price: 25_000.0,
      holy_grail_signal: :none,
      trend_analysis: :none,
      option_premium: 135.0,
      expected_trade: :none
    }
  end

  def create_profitable_position_scenario
    {
      entry_price: 150.0,
      current_price: 200.0,
      quantity: 75,
      expected_pnl: 3750.0,
      expected_pnl_pct: 33.33
    }
  end

  def create_losing_position_scenario
    {
      entry_price: 150.0,
      current_price: 100.0,
      quantity: 75,
      expected_pnl: -3750.0,
      expected_pnl_pct: -33.33
    }
  end

  def create_risk_limit_breach_scenario
    {
      total_pnl: -6000.0,
      max_day_loss: 5000.0,
      should_trigger: true
    }
  end

  def create_position_limit_scenario
    {
      current_positions: 5,
      max_positions: 5,
      should_allow_new: false
    }
  end

  # Helper methods for performance testing
  def measure_execution_time(&)
    start_time = Time.now
    yield
    end_time = Time.now
    end_time - start_time
  end

  def simulate_high_frequency_updates(app, count: 1000)
    count.times do |i|
      price_data = {
        instrument_id: "TEST#{i % 10}",
        segment: "NSE_FNO",
        ltp: 150.0 + i,
        timestamp: Time.now.to_i
      }
      app.send(:handle_price_update, price_data)
    end
  end

  def simulate_concurrent_access(app, thread_count: 10, operations_per_thread: 100)
    threads = []

    thread_count.times do |i|
      threads << Thread.new do
        operations_per_thread.times do |j|
          app.send(:analyze_and_trade)
          app.send(:check_risk_limits)
        end
      end
    end

    threads.each(&:join)
    threads
  end

  # Helper methods for data validation
  def validate_position_data(position)
    expect(position).to include(
      :symbol, :option_type, :strike, :expiry, :instrument_id,
      :quantity, :entry_price, :current_price, :pnl, :created_at
    )
    expect(position[:quantity]).to be > 0
    expect(position[:entry_price]).to be > 0
    expect(position[:current_price]).to be > 0
  end

  def validate_order_data(order)
    expect(order).to include(:id, :security_id, :side, :quantity, :price, :timestamp)
    expect(order[:quantity]).to be > 0
    expect(order[:price]).to be > 0
    expect(%w[BUY SELL]).to include(order[:side])
  end

  def validate_balance_data(balance)
    expect(balance).to include(:available, :used, :total)
    expect(balance[:available]).to be >= 0
    expect(balance[:used]).to be >= 0
    expect(balance[:total]).to be >= 0
    expect(balance[:total]).to eq(balance[:available] + balance[:used])
  end

  def validate_session_data(session_data)
    expect(session_data).to include(
      :total_trades, :successful_trades, :failed_trades, :total_pnl
    )
    expect(session_data[:total_trades]).to eq(
      session_data[:successful_trades] + session_data[:failed_trades]
    )
    expect(session_data[:successful_trades]).to be >= 0
    expect(session_data[:failed_trades]).to be >= 0
  end

  # Helper methods for error testing
  def simulate_websocket_disconnection(app)
    mock_ws_manager = app.instance_variable_get(:@websocket_manager)
    allow(mock_ws_manager).to receive(:connected?).and_return(false)
  end

  def simulate_api_rate_limiting(app)
    allow(app).to receive(:get_holy_grail_signal).and_raise(
      StandardError, "Rate limit exceeded"
    )
  end

  def simulate_csv_loading_failure(app)
    mock_csv_master = app.instance_variable_get(:@csv_master)
    allow(mock_csv_master).to receive(:get_expiry_dates).and_raise(
      StandardError, "CSV loading failed"
    )
  end

  def simulate_insufficient_balance(app)
    mock_balance_provider = app.instance_variable_get(:@balance_provider)
    allow(mock_balance_provider).to receive(:available_balance).and_return(0.0)
  end

  # Helper methods for cleanup
  def cleanup_test_data
    FileUtils.rm_rf("test_data") if File.directory?("test_data")
    FileUtils.rm_rf("data") if File.directory?("data")
    GC.start
  end

  def reset_environment_variables
    ENV.delete("SCALPER_CONFIG")
    ENV.delete("CLIENT_ID")
    ENV.delete("ACCESS_TOKEN")
    ENV.delete("TICK_CACHE_BACKEND")
  end

  # Helper methods for assertions
  def expect_successful_trade_execution(result)
    expect(result).to be true
  end

  def expect_failed_trade_execution(result)
    expect(result).to be false
  end

  def expect_position_created(positions, symbol, option_type, strike)
    position = positions.find do |p|
      p[:symbol] == symbol && p[:option_type] == option_type && p[:strike] == strike
    end
    expect(position).not_to be_nil
  end

  def expect_position_removed(positions, symbol, option_type, strike)
    position = positions.find do |p|
      p[:symbol] == symbol && p[:option_type] == option_type && p[:strike] == strike
    end
    expect(position).to be_nil
  end

  def expect_balance_updated(balance, expected_available, expected_used)
    expect(balance[:available]).to eq(expected_available)
    expect(balance[:used]).to eq(expected_used)
  end

  def expect_pnl_calculated_correctly(position, expected_pnl)
    calculated_pnl = (position[:current_price] - position[:entry_price]) * position[:quantity]
    expect(calculated_pnl).to eq(expected_pnl)
  end

  # Helper methods for logging and debugging
  def log_test_progress(message)
    puts "[TEST] #{message}" if ENV["VERBOSE_TESTS"]
  end

  def log_performance_metrics(operation, duration, count = 1)
    avg_duration = duration / count
    return unless ENV["VERBOSE_TESTS"]

    puts "[PERF] #{operation}: #{duration.round(3)}s total, #{avg_duration.round(3)}s avg (#{count} operations)"
  end

  def log_memory_usage
    memory_kb = `ps -o rss= -p #{Process.pid}`.to_i
    puts "[MEMORY] Current usage: #{memory_kb} KB" if ENV["VERBOSE_TESTS"]
  end
end

# Include test helpers in RSpec
RSpec.configure do |config|
  config.include TestHelpers
  config.include TestData
end
