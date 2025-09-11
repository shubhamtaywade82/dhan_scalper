#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "dhan_scalper"

puts "🎯 DhanScalper Trading Logic Testing with Real NIFTY Data"
puts "=" * 60

# Load actual NIFTY data and live LTP for trading logic tests
def load_nifty_data_for_trading_logic
  puts "\n📈 Loading actual NIFTY data for trading logic testing..."
  begin
    # Load configuration
    DhanScalper::Config.load(path: "config/scalper.yml")

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
      puts "  Date range: #{Time.at(series.candles.first.timestamp).strftime("%Y-%m-%d %H:%M")} to #{Time.at(series.candles.last.timestamp).strftime("%Y-%m-%d %H:%M")}"
      puts "  Price range: ₹#{series.candles.map(&:low).min.round(2)} - ₹#{series.candles.map(&:high).max.round(2)}"

      # Get current LTP from the latest candle
      current_ltp = series.candles.last.close
      puts "  Current NIFTY LTP: ₹#{current_ltp.round(2)}"

      { series: series, current_ltp: current_ltp }
    else
      puts "  ⚠️ No historical data available, using mock data as fallback"
      create_fallback_data_for_trading_logic
    end
  rescue StandardError => e
    puts "  ⚠️ Failed to load real data: #{e.message}"
    puts "  Using mock data as fallback"
    create_fallback_data_for_trading_logic
  end
end

# Fallback to mock data if real data fails
def create_fallback_data_for_trading_logic
  puts "  Creating fallback mock data for trading logic testing..."
  series = CandleSeries.new(symbol: "NIFTY", interval: "1")

  # Create realistic mock data based on current NIFTY levels
  base_price = 19_500.0
  candles = []

  200.times do |i|
    # Create realistic price movement
    change = (rand - 0.5) * 50 # Random change between -25 and +25
    open = base_price + change
    high = open + rand(30)
    low = open - rand(30)
    close = low + rand(high - low)
    volume = rand(5000..50_000)

    candles << Candle.new(
      ts: Time.now.to_i - ((200 - i) * 60), # 1 minute intervals
      open: open,
      high: high,
      low: low,
      close: close,
      volume: volume
    )

    base_price = close # Next candle starts from previous close
  end

  candles.each { |candle| series.candles << candle }
  current_ltp = series.candles.last.close
  puts "  ✓ Created #{series.candles.size} mock candles for trading logic testing"
  puts "  Mock NIFTY LTP: ₹#{current_ltp.round(2)}"

  { series: series, current_ltp: current_ltp }
end

# Load real NIFTY data once for all trading logic tests
nifty_data = load_nifty_data_for_trading_logic
nifty_series = nifty_data[:series]
current_nifty_ltp = nifty_data[:current_ltp]

# Test 1: Basic Trend Engine
puts "\n1. Testing Basic Trend Engine..."
begin
  DhanScalper::Trend.new(seg_idx: "IDX_I", sid_idx: "13")
  puts "✓ Basic Trend engine created"
  puts "  Segment: IDX_I"
  puts "  Security ID: 13"

  # NOTE: This will try to fetch real data, so it might fail without API
  puts "  (Note: Will attempt to fetch real market data)"
rescue StandardError => e
  puts "✗ Basic Trend failed: #{e.message}"
  puts "  (Expected if no API credentials or market closed)"
end

# Test 2: Enhanced Trend Engine with Real Data
puts "\n2. Testing Enhanced Trend Engine with Real NIFTY Data..."
begin
  DhanScalper::TrendEnhanced.new(
    seg_idx: "IDX_I",
    sid_idx: "13",
    use_multi_timeframe: true,
    secondary_timeframe: 5
  )
  puts "✓ Enhanced Trend engine created"
  puts "  Multi-timeframe: true"
  puts "  Secondary timeframe: 5 minutes"

  # Test with real NIFTY data
  puts "  Testing with real NIFTY data..."
  if nifty_series.candles.size > 0
    puts "  ✓ Using #{nifty_series.candles.size} real NIFTY candles"
    puts "  Current NIFTY LTP: ₹#{current_nifty_ltp.round(2)}"

    # Test Holy Grail analysis on real data
    holy_grail = nifty_series.holy_grail
    if holy_grail
      puts "  Holy Grail Analysis:"
      puts "    Bias: #{holy_grail.bias}"
      puts "    Momentum: #{holy_grail.momentum}"
      puts "    ADX: #{holy_grail.adx.round(2)}"
      puts "    Proceed: #{holy_grail.proceed?}"
    end
  else
    puts "  ⚠️ No real data available for trend analysis"
  end
rescue StandardError => e
  puts "✗ Enhanced Trend failed: #{e.message}"
  puts e.backtrace.first(3).join("\n")
end

# Test 3: Option Picker
puts "\n3. Testing Option Picker..."
begin
  config = DhanScalper::Config.load(path: "config/scalper.yml")
  nifty_config = config["SYMBOLS"]["NIFTY"]

  picker = DhanScalper::OptionPicker.new(nifty_config, mode: :paper)
  puts "✓ Option Picker created"
  puts "  Mode: paper"
  puts "  Index SID: #{nifty_config["idx_sid"]}"
  puts "  Strike Step: #{nifty_config["strike_step"]}"
  puts "  Lot Size: #{nifty_config["lot_size"]}"

  # Test picking options with real NIFTY LTP
  puts "  Using real NIFTY LTP: ₹#{current_nifty_ltp.round(2)}"
  pick_result = picker.pick(current_spot: current_nifty_ltp)

  if pick_result
    puts "✓ Option picking successful"
    puts "  Expiry: #{pick_result[:expiry]}"
    puts "  Strikes: #{pick_result[:strikes].join(", ")}"
    puts "  CE SID: #{pick_result[:ce_sid]}"
    puts "  PE SID: #{pick_result[:pe_sid]}"
  else
    puts "✗ Option picking failed"
  end
rescue StandardError => e
  puts "✗ Option Picker failed: #{e.message}"
  puts e.backtrace.first(3).join("\n")
end

# Test 4: CSV Master Integration
puts "\n4. Testing CSV Master Integration..."
begin
  csv_master = DhanScalper::CsvMaster.new
  puts "✓ CSV Master created"

  # Test getting expiry dates
  expiry_dates = csv_master.get_expiry_dates("NIFTY")
  if expiry_dates.any?
    puts "✓ Expiry dates retrieved"
    puts "  Available expiries: #{expiry_dates.size}"
    puts "  Next expiry: #{expiry_dates.first}"
  else
    puts "✗ No expiry dates found"
  end

  # Test getting available strikes
  if expiry_dates.any?
    strikes = csv_master.get_available_strikes("NIFTY", expiry_dates.first)
    if strikes.any?
      puts "✓ Available strikes retrieved"
      puts "  Strikes count: #{strikes.size}"
      puts "  Sample strikes: #{strikes.first(5).join(", ")}"
    else
      puts "✗ No strikes found"
    end
  end
rescue StandardError => e
  puts "✗ CSV Master failed: #{e.message}"
  puts e.backtrace.first(3).join("\n")
end

# Test 5: PnL Calculations with Real NIFTY Data
puts "\n5. Testing PnL Calculations with Real NIFTY Data..."
begin
  # Test PnL module with realistic NIFTY-based prices
  charge_per_order = 20.0
  entry = current_nifty_ltp
  # Use a price from earlier in the series for realistic LTP simulation
  # Handle case where we don't have enough candles
  ltp = if nifty_series.candles.size >= 2
          nifty_series.candles[-2].close # Price from 2 candles ago
        else
          entry * 1.05 # 5% profit simulation
        end
  lot_size = 75
  qty_lots = 1

  net_pnl = DhanScalper::PnL.net(
    entry: entry,
    ltp: ltp,
    lot_size: lot_size,
    qty_lots: qty_lots,
    charge_per_order: charge_per_order
  )

  price_change = ((ltp - entry) / entry * 100).round(2)
  puts "✓ PnL calculation successful with real NIFTY data"
  puts "  Entry: ₹#{entry.round(2)} (Current NIFTY LTP)"
  puts "  LTP: ₹#{ltp.round(2)} (Historical NIFTY price)"
  puts "  Price Change: #{price_change}%"
  puts "  Lot Size: #{lot_size}"
  puts "  Quantity Lots: #{qty_lots}"
  puts "  Charge per Order: ₹#{charge_per_order}"
  puts "  Net PnL: ₹#{net_pnl.round(2)}"

  # Test round trip charges
  round_trip = DhanScalper::PnL.round_trip_orders(charge_per_order)
  puts "  Round Trip Charges: ₹#{round_trip}"
rescue StandardError => e
  puts "✗ PnL calculations failed: #{e.message}"
  puts e.backtrace.first(3).join("\n")
end

# Test 6: State Management
puts "\n6. Testing State Management..."
begin
  state = DhanScalper::State.new(
    symbols: ["NIFTY"],
    session_target: 1000.0,
    max_day_loss: 1500.0
  )

  puts "✓ State created successfully"
  puts "  Symbols: #{state.symbols.join(", ")}"
  puts "  Session Target: ₹#{state.session_target}"
  puts "  Max Day Loss: ₹#{state.max_day_loss}"
  puts "  Status: #{state.status}"

  # Test PnL tracking
  state.set_session_pnl(500.0)
  puts "  Session PnL: ₹#{state.pnl}"

  # Test status changes
  state.set_status(:paused)
  puts "  Status after pause: #{state.status}"

  state.set_status(:running)
  puts "  Status after resume: #{state.status}"
rescue StandardError => e
  puts "✗ State management failed: #{e.message}"
  puts e.backtrace.first(3).join("\n")
end

puts "\n" + ("=" * 50)
puts "🎯 Trading Logic Testing Completed!"
