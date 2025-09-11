# frozen_string_literal: true

module TestData
  # Sample configuration for testing
  SAMPLE_CONFIG = {
    "global" => {
      "min_profit_target" => 1000,
      "max_day_loss" => 5000,
      "decision_interval" => 10,
      "log_level" => "INFO",
      "use_multi_timeframe" => true,
      "secondary_timeframe" => 5,
      "charge_per_order" => 20,
      "allocation_pct" => 0.30,
      "slippage_buffer_pct" => 0.01,
      "max_lots_per_trade" => 10,
      "tp_pct" => 0.35,
      "sl_pct" => 0.18,
      "trail_pct" => 0.12
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
  }.freeze

  # Sample candle data for testing
  SAMPLE_CANDLES = [
    {
      timestamp: Time.now - 300,
      open: 25_000.0,
      high: 25_050.0,
      low: 24_950.0,
      close: 25_025.0,
      volume: 1000
    },
    {
      timestamp: Time.now - 240,
      open: 25_025.0,
      high: 25_075.0,
      low: 25_000.0,
      close: 25_050.0,
      volume: 1200
    },
    {
      timestamp: Time.now - 180,
      open: 25_050.0,
      high: 25_100.0,
      low: 25_025.0,
      close: 25_075.0,
      volume: 1100
    },
    {
      timestamp: Time.now - 120,
      open: 25_075.0,
      high: 25_125.0,
      low: 25_050.0,
      close: 25_100.0,
      volume: 1300
    },
    {
      timestamp: Time.now - 60,
      open: 25_100.0,
      high: 25_150.0,
      low: 25_075.0,
      close: 25_125.0,
      volume: 1400
    }
  ].freeze

  # Sample tick data for testing
  SAMPLE_TICK_DATA = {
    segment: "NSE_FNO",
    security_id: "TEST123",
    ltp: 150.0,
    open: 145.0,
    high: 155.0,
    low: 140.0,
    close: 148.0,
    volume: 1000,
    timestamp: Time.now.to_i,
    day_high: 155.0,
    day_low: 140.0,
    atp: 150.0,
    vol: 1000
  }.freeze

  # Sample position data for testing
  SAMPLE_POSITION = {
    symbol: "NIFTY",
    option_type: "CE",
    strike: 25_000,
    expiry: Date.today,
    instrument_id: "TEST123",
    quantity: 75,
    entry_price: 150.0,
    current_price: 150.0,
    pnl: 0.0,
    created_at: Time.now
  }.freeze

  # Sample order data for testing
  SAMPLE_ORDER = {
    id: "P-1234567890",
    security_id: "TEST123",
    side: "BUY",
    quantity: 75,
    price: 150.0,
    timestamp: Time.now
  }.freeze

  # Sample balance data for testing
  SAMPLE_BALANCE = {
    available: 200_000.0,
    used: 0.0,
    total: 200_000.0
  }.freeze

  # Sample CSV master data for testing
  SAMPLE_CSV_DATA = [
    {
      "UNDERLYING_SYMBOL" => "NIFTY",
      "INSTRUMENT" => "OPTIDX",
      "SM_EXPIRY_DATE" => "2024-12-26",
      "STRIKE_PRICE" => "25000",
      "OPTION_TYPE" => "CE",
      "SECURITY_ID" => "TEST123",
      "LOT_SIZE" => "75",
      "EXCHANGE" => "NSE",
      "SEGMENT" => "FNO"
    },
    {
      "UNDERLYING_SYMBOL" => "NIFTY",
      "INSTRUMENT" => "OPTIDX",
      "SM_EXPIRY_DATE" => "2024-12-26",
      "STRIKE_PRICE" => "25000",
      "OPTION_TYPE" => "PE",
      "SECURITY_ID" => "TEST124",
      "LOT_SIZE" => "75",
      "EXCHANGE" => "NSE",
      "SEGMENT" => "FNO"
    },
    {
      "UNDERLYING_SYMBOL" => "NIFTY",
      "INSTRUMENT" => "INDEX",
      "SM_EXPIRY_DATE" => "",
      "STRIKE_PRICE" => "",
      "OPTION_TYPE" => "",
      "SECURITY_ID" => "13",
      "LOT_SIZE" => "75",
      "EXCHANGE" => "NSE",
      "SEGMENT" => "I"
    }
  ].freeze

  # Sample Holy Grail signal data
  SAMPLE_HOLY_GRAIL_SIGNAL = {
    bias: :bullish,
    momentum: :strong,
    adx: 25.0,
    rsi: 65.0,
    macd: :bullish,
    signal_strength: 0.8
  }.freeze

  # Sample trend analysis data
  SAMPLE_TREND_ANALYSIS = {
    primary_trend: :bullish,
    secondary_trend: :bullish,
    trend_strength: 0.75,
    trend_duration: 300,
    signal_quality: :high
  }.freeze

  # Sample session statistics
  SAMPLE_SESSION_STATS = {
    total_trades: 5,
    successful_trades: 4,
    failed_trades: 1,
    total_pnl: 1500.0,
    max_profit: 2000.0,
    max_drawdown: -500.0,
    win_rate: 0.8,
    avg_trade_pnl: 300.0,
    symbols_traded: Set.new(["NIFTY"]),
    session_duration: 3600,
    start_time: Time.now - 3600,
    end_time: Time.now
  }.freeze

  # Sample Redis data for testing
  SAMPLE_REDIS_DATA = {
    "dhan_scalper:v1:ticks:NSE_FNO:TEST123" => {
      "ltp" => "150.0",
      "open" => "145.0",
      "high" => "155.0",
      "low" => "140.0",
      "close" => "148.0",
      "volume" => "1000",
      "timestamp" => Time.now.to_i.to_s,
      "day_high" => "155.0",
      "day_low" => "140.0",
      "atp" => "150.0",
      "vol" => "1000"
    },
    "dhan_scalper:v1:pos:TEST123" => {
      "symbol" => "NIFTY",
      "option_type" => "CE",
      "strike" => "25000",
      "expiry" => Date.today.to_s,
      "instrument_id" => "TEST123",
      "quantity" => "75",
      "entry_price" => "150.0",
      "current_price" => "150.0",
      "pnl" => "0.0",
      "created_at" => Time.now.to_s
    }
  }.freeze

  # Sample WebSocket message data
  SAMPLE_WEBSOCKET_MESSAGE = {
    type: "tick",
    data: {
      security_id: "TEST123",
      segment: "NSE_FNO",
      ltp: 150.0,
      open: 145.0,
      high: 155.0,
      low: 140.0,
      close: 148.0,
      volume: 1000,
      timestamp: Time.now.to_i,
      day_high: 155.0,
      day_low: 140.0,
      atp: 150.0,
      vol: 1000
    }
  }.freeze

  # Sample error scenarios for testing
  SAMPLE_ERRORS = {
    websocket_connection_failed: StandardError.new("WebSocket connection failed"),
    api_rate_limit_exceeded: StandardError.new("Rate limit exceeded"),
    csv_data_loading_failed: StandardError.new("CSV data loading failed"),
    insufficient_balance: StandardError.new("Insufficient balance"),
    invalid_security_id: ArgumentError.new("Invalid security ID"),
    network_timeout: Timeout::Error.new("Request timeout"),
    json_parsing_error: JSON::ParserError.new("Invalid JSON")
  }.freeze

  # Sample performance metrics
  SAMPLE_PERFORMANCE_METRICS = {
    signal_processing_time: 0.05, # 50ms
    order_execution_time: 0.1,    # 100ms
    position_update_time: 0.02,   # 20ms
    memory_usage: 50_000,         # 50MB
    cpu_usage: 25.0,              # 25%
    network_latency: 0.1,         # 100ms
    cache_hit_ratio: 0.95,        # 95%
    error_rate: 0.01              # 1%
  }.freeze

  # Helper methods for creating test data
  def self.create_candle_series(symbol: "NIFTY", interval: "1m", count: 100)
    candles = []
    base_price = 25_000.0
    base_time = Time.now - (count * 60)

    count.times do |i|
      candles << {
        timestamp: base_time + (i * 60),
        open: base_price + (i * 10),
        high: base_price + (i * 10) + 25,
        low: base_price + (i * 10) - 25,
        close: base_price + (i * 10) + 5,
        volume: 1000 + (i * 10)
      }
    end

    candles
  end

  def self.create_position_data(symbol: "NIFTY", count: 10)
    positions = []

    count.times do |i|
      positions << {
        symbol: symbol,
        option_type: i.even? ? "CE" : "PE",
        strike: 25_000 + (i * 50),
        expiry: Date.today,
        instrument_id: "TEST#{i}",
        quantity: 75,
        entry_price: 150.0 + (i * 10),
        current_price: 150.0 + (i * 10) + (i * 5),
        pnl: (i * 5) * 75,
        created_at: Time.now - (i * 300)
      }
    end

    positions
  end

  def self.create_order_data(count: 20)
    orders = []

    count.times do |i|
      orders << {
        id: "P-#{Time.now.to_f}_#{i}",
        security_id: "TEST#{i % 10}",
        side: i.even? ? "BUY" : "SELL",
        quantity: 75,
        price: 150.0 + (i * 5),
        timestamp: Time.now - (i * 60)
      }
    end

    orders
  end

  def self.create_tick_data(security_id: "TEST123", count: 100)
    ticks = []
    base_price = 150.0
    base_time = Time.now.to_i - (count * 60)

    count.times do |i|
      ticks << {
        segment: "NSE_FNO",
        security_id: security_id,
        ltp: base_price + (i * 0.5),
        open: base_price + (i * 0.5) - 2.5,
        high: base_price + (i * 0.5) + 2.5,
        low: base_price + (i * 0.5) - 2.5,
        close: base_price + (i * 0.5),
        volume: 1000 + (i * 10),
        timestamp: base_time + (i * 60),
        day_high: base_price + (i * 0.5) + 2.5,
        day_low: base_price + (i * 0.5) - 2.5,
        atp: base_price + (i * 0.5),
        vol: 1000 + (i * 10)
      }
    end

    ticks
  end

  def self.create_session_data(session_id: "TEST_SESSION")
    {
      session_id: session_id,
      mode: "paper",
      start_time: Time.now - 3600,
      end_time: Time.now,
      duration: 3600,
      symbols: ["NIFTY"],
      total_trades: 10,
      successful_trades: 8,
      failed_trades: 2,
      total_pnl: 2000.0,
      max_profit: 3000.0,
      max_drawdown: -500.0,
      win_rate: 0.8,
      avg_trade_pnl: 200.0,
      starting_balance: 200_000.0,
      ending_balance: 202_000.0,
      balance_change_pct: 1.0
    }
  end

  # Mock data generators for testing
  def self.mock_dhanhq_response
    {
      "status" => "success",
      "data" => {
        "available_balance" => 200_000.0,
        "utilized_amount" => 0.0,
        "total_balance" => 200_000.0
      }
    }
  end

  def self.mock_websocket_tick
    {
      security_id: "TEST123",
      segment: "NSE_FNO",
      ltp: 150.0,
      open: 145.0,
      high: 155.0,
      low: 140.0,
      close: 148.0,
      volume: 1000,
      timestamp: Time.now.to_i,
      day_high: 155.0,
      day_low: 140.0,
      atp: 150.0,
      vol: 1000
    }
  end

  def self.mock_historical_data
    {
      "status" => "success",
      "data" => [
        {
          "timestamp" => (Time.now - 300).to_i,
          "open" => 25_000.0,
          "high" => 25_050.0,
          "low" => 24_950.0,
          "close" => 25_025.0,
          "volume" => 1000
        },
        {
          "timestamp" => (Time.now - 240).to_i,
          "open" => 25_025.0,
          "high" => 25_075.0,
          "low" => 25_000.0,
          "close" => 25_050.0,
          "volume" => 1200
        }
      ]
    }
  end
end
