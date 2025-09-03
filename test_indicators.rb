#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "dhan_scalper"

puts "📊 DhanScalper Technical Indicators Testing with Real NIFTY Data"
puts "=" * 60

# Load actual NIFTY data
def load_nifty_data
  puts "\n📈 Loading actual NIFTY historical data..."
  begin
    # Load configuration
    config = DhanScalper::Config.load(path: "config/scalper.yml")

    # Create CandleSeries and fetch real data
    series = CandleSeries.new(symbol: "NIFTY", interval: "1")

    # Fetch historical data (this will use rate limiting and caching)
    puts "  Fetching 1-minute NIFTY data from DhanHQ..."
    # NIFTY segment and security ID
    historical_data = CandleSeries.fetch_historical_data("IDX_I", "13", "1")

    if historical_data && historical_data.any?
      # Load the data into the series
      series.load_from_raw(historical_data)
      puts "  ✓ Loaded #{series.candles.size} real NIFTY candles"

      puts "  Date range: #{Time.at(series.candles.first.timestamp).strftime('%Y-%m-%d %H:%M')} to #{Time.at(series.candles.last.timestamp).strftime('%Y-%m-%d %H:%M')}"
      puts "  Price range: ₹#{series.candles.map(&:low).min.round(2)} - ₹#{series.candles.map(&:high).max.round(2)}"
      return series
    else
      puts "  ⚠️ No historical data available, using mock data as fallback"
      return create_fallback_data
    end

  rescue StandardError => e
    puts "  ⚠️ Failed to load real data: #{e.message}"
    puts "  Using mock data as fallback"
    return create_fallback_data
  end
end

# Fallback to mock data if real data fails
def create_fallback_data
  puts "  Creating fallback mock data..."
  series = CandleSeries.new(symbol: "NIFTY", interval: "1")

  # Create realistic mock data based on current NIFTY levels
  base_price = 19500.0
  candles = []

  200.times do |i|
    # Create realistic price movement
    change = (rand - 0.5) * 50 # Random change between -25 and +25
    open = base_price + change
    high = open + rand(30)
    low = open - rand(30)
    close = low + rand(high - low)
    volume = rand(5000..50000)

    candles << Candle.new(
      ts: Time.now.to_i - (200 - i) * 60, # 1 minute intervals
      open: open,
      high: high,
      low: low,
      close: close,
      volume: volume
    )

    base_price = close # Next candle starts from previous close
  end

  candles.each { |candle| series.candles << candle }
  puts "  ✓ Created #{series.candles.size} mock candles"
  series
end

# Load real NIFTY data once for all tests
nifty_series = load_nifty_data

# Test 1: CandleSeries with Indicators
puts "\n1. Testing CandleSeries with Indicators..."
begin
  series = nifty_series.dup # Use a copy for this test

  puts "✓ CandleSeries created with #{series.candles.size} real NIFTY candles"

  # Test basic indicators
  if series.candles.size >= 20
    sma_20 = series.sma(20)
    puts "✓ SMA(20): #{sma_20.is_a?(Array) ? sma_20.last.round(2) : sma_20.round(2)}"
  end

  if series.candles.size >= 50
    sma_50 = series.sma(50)
    puts "✓ SMA(50): #{sma_50.is_a?(Array) ? sma_50.last.round(2) : sma_50.round(2)}"
  end

  # Test MACD
  macd_result = series.macd
  pp macd_result
  if macd_result && macd_result.is_a?(Hash)
    puts "✓ MACD: #{macd_result[:macd].round(4)}"
    puts "  Signal: #{macd_result[:signal].round(4)}"
    puts "  Histogram: #{macd_result[:histogram].round(4)}"
  elsif macd_result
    puts "✓ MACD: #{macd_result}"
  end

  # Test Bollinger Bands
  bb = series.bollinger_bands
  if bb && bb.is_a?(Hash)
    puts "✓ Bollinger Bands:"
    puts "  Upper: #{bb[:upper].round(2)}"
    puts "  Middle: #{bb[:middle].round(2)}"
    puts "  Lower: #{bb[:lower].round(2)}"
  elsif bb
    puts "✓ Bollinger Bands: #{bb}"
  end

  # Test ATR
  atr = series.atr
  if atr
    puts "✓ ATR(14): #{atr.last.round(2)}"
  end

rescue StandardError => e
  puts "✗ CandleSeries indicators failed: #{e.message}"
  puts e.backtrace.first(3).join("\n")
end

# Test 2: Holy Grail Indicator
puts "\n2. Testing Holy Grail Indicator..."
begin
  series = nifty_series.dup # Use real NIFTY data

  holy_grail = series.holy_grail
  if holy_grail
    puts "✓ Holy Grail analysis completed"
    puts "  Bias: #{holy_grail.bias}"
    puts "  Momentum: #{holy_grail.momentum}"
    puts "  ADX: #{holy_grail.adx.round(2)}"
    puts "  Proceed: #{holy_grail.proceed?}"
    puts "  SMA50: #{holy_grail.sma50.round(2)}"
    puts "  EMA200: #{holy_grail.ema200.round(2)}"
    puts "  RSI14: #{holy_grail.rsi14.round(2)}"
    puts "  Trend: #{holy_grail.trend}"
  else
    puts "✗ Holy Grail analysis failed"
  end

rescue StandardError => e
  puts "✗ Holy Grail failed: #{e.message}"
  puts e.backtrace.first(3).join("\n")
end

# Test 3: Supertrend Indicator
puts "\n3. Testing Supertrend Indicator..."
begin
  series = nifty_series.dup # Use real NIFTY data

  # Test Supertrend
  st_values = series.supertrend_new(period: 10, multiplier: 2.0)
  if st_values.any?
    puts "✓ Supertrend calculated"
    puts "  Latest Supertrend: #{st_values.last.round(2)}"
    puts "  Current Price: #{series.closes.last.round(2)}"

    # Test signal
    signal = series.supertrend_signal
    puts "  Signal: #{signal}"
  else
    puts "✗ Supertrend calculation failed"
  end

rescue StandardError => e
  puts "✗ Supertrend failed: #{e.message}"
  puts e.backtrace.first(3).join("\n")
end

# Test 4: Combined Signal
puts "\n4. Testing Combined Signal..."
begin
  series = nifty_series.dup # Use real NIFTY data

  combined_signal = series.combined_signal
  puts "✓ Combined signal: #{combined_signal}"

rescue StandardError => e
  puts "✗ Combined signal failed: #{e.message}"
  puts e.backtrace.first(3).join("\n")
end

# Test 5: Direct Holy Grail Class
puts "\n5. Testing Holy Grail Class Directly..."
begin
  series = nifty_series.dup # Use real NIFTY data

  holy_grail = DhanScalper::Indicators::HolyGrail.new(candles: series.to_hash).call
  if holy_grail
    puts "✓ Direct Holy Grail class working"
    puts "  Bias: #{holy_grail.bias}"
    puts "  Momentum: #{holy_grail.momentum}"
    puts "  ADX: #{holy_grail.adx.round(2)}"
    puts "  Proceed: #{holy_grail.proceed?}"
  else
    puts "✗ Direct Holy Grail class failed"
  end

rescue StandardError => e
  puts "✗ Direct Holy Grail class failed: #{e.message}"
  puts e.backtrace.first(3).join("\n")
end

# Test 6: Direct Supertrend Class
puts "\n6. Testing Supertrend Class Directly..."
begin
  series = nifty_series.dup # Use real NIFTY data

  supertrend = DhanScalper::Indicators::Supertrend.new(series: series).call
  if supertrend.any?
    puts "✓ Direct Supertrend class working"
    puts "  Latest value: #{supertrend.last.round(2)}"
    puts "  Values count: #{supertrend.size}"
  else
    puts "✗ Direct Supertrend class failed"
  end

rescue StandardError => e
  puts "✗ Direct Supertrend class failed: #{e.message}"
  puts e.backtrace.first(3).join("\n")
end

puts "\n" + "=" * 50
puts "🎯 Technical Indicators Testing Completed!"