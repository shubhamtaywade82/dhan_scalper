#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "dhan_scalper"

puts "🔗 DhanScalper Integration Testing with Real NIFTY Data"
puts "=" * 60

# Load actual NIFTY data for integration tests
def load_nifty_data_for_integration
  puts "\n📈 Loading actual NIFTY data for integration testing..."
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
      return create_fallback_data_for_integration
    end

  rescue StandardError => e
    puts "  ⚠️ Failed to load real data: #{e.message}"
    puts "  Using mock data as fallback"
    return create_fallback_data_for_integration
  end
end

# Fallback to mock data if real data fails
def create_fallback_data_for_integration
  puts "  Creating fallback mock data for integration testing..."
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
  puts "  ✓ Created #{series.candles.size} mock candles for integration testing"
  series
end

# Load real NIFTY data once for all integration tests
nifty_series = load_nifty_data_for_integration

# Test 1: Full Paper Trading Workflow
puts "\n1. Testing Full Paper Trading Workflow..."
begin
  config = DhanScalper::Config.load(path: "config/scalper.yml")

  # Initialize all components
  vdm = DhanScalper::VirtualDataManager.new
  wallet = DhanScalper::BalanceProviders::PaperWallet.new(starting_balance: 100_000)
  broker = DhanScalper::Brokers::PaperBroker.new(
    virtual_data_manager: vdm,
    balance_provider: wallet
  )
  sizer = DhanScalper::QuantitySizer.new(config, wallet)

  puts "✓ All components initialized"
  puts "  VDM: #{vdm.class}"
  puts "  Wallet: #{wallet.class}"
  puts "  Broker: #{broker.class}"
  puts "  Sizer: #{sizer.class}"

  # Test complete trading workflow
  puts "\n  Testing complete trading workflow with real NIFTY data..."

  # 1. Add real NIFTY market data
  current_nifty_price = nifty_series.candles.last.close
  puts "  Current NIFTY price: ₹#{current_nifty_price.round(2)}"

  DhanScalper::TickCache.put({
    segment: "IDX_I",
    security_id: "13",
    ltp: current_nifty_price,
    ts: Time.now.to_i,
    symbol: "NIFTY"
  })

  # 2. Calculate position size using real NIFTY price
  lots = sizer.calculate_lots("NIFTY", current_nifty_price)
  puts "  Position size calculated: #{lots} lots"

  # 3. Place order
  if lots > 0
    order = broker.buy_market(
      segment: "NSE_FNO",
      security_id: "CE123",
      quantity: lots * config["SYMBOLS"]["NIFTY"]["lot_size"],
      charge_per_order: 20
    )

    if order
      puts "  Order placed: #{order.id}"
      puts "  Balance after order: ₹#{wallet.available_balance}"

      # 4. Check VDM data
      orders = vdm.get_orders
      positions = vdm.get_positions
      puts "  VDM orders: #{orders.size}"
      puts "  VDM positions: #{positions.size}"

      # 5. Simulate price change using real NIFTY data and close position
      # Use a price from earlier in the day for realistic simulation
      simulated_price = nifty_series.candles[-10].close # Price from 10 candles ago
      price_change = ((simulated_price - current_nifty_price) / current_nifty_price * 100).round(2)
      puts "  Simulating price change: #{price_change}%"

      DhanScalper::TickCache.put({
        segment: "IDX_I",
        security_id: "13",
        ltp: simulated_price,
        ts: Time.now.to_i,
        symbol: "NIFTY"
      })

      # 6. Close position
      close_order = broker.sell_market(
        segment: "NSE_FNO",
        security_id: "CE123",
        quantity: lots * config["SYMBOLS"]["NIFTY"]["lot_size"],
        charge_per_order: 20
      )

      if close_order
        puts "  Position closed: #{close_order.id}"
        puts "  Final balance: ₹#{wallet.available_balance}"

        # Calculate PnL using real prices
        net_pnl = DhanScalper::PnL.net(
          entry: current_nifty_price,
          ltp: simulated_price,
          lot_size: config["SYMBOLS"]["NIFTY"]["lot_size"],
          qty_lots: lots,
          charge_per_order: 20
        )
        puts "  Net PnL: ₹#{net_pnl.round(2)}"
      end
    end
  end

rescue StandardError => e
  puts "✗ Paper trading workflow failed: #{e.message}"
  puts e.backtrace.first(3).join("\n")
end

# Test 2: CSV Master Integration
puts "\n2. Testing CSV Master Integration..."
begin
  csv_master = DhanScalper::CsvMaster.new
  config = DhanScalper::Config.load(path: "config/scalper.yml")
  nifty_config = config["SYMBOLS"]["NIFTY"]

  # Test option picker with real CSV data
  picker = DhanScalper::OptionPicker.new(nifty_config, mode: :paper)

  # Get real expiry dates
  expiry_dates = csv_master.get_expiry_dates("NIFTY")
  puts "✓ CSV Master integration working"
  puts "  Available expiries: #{expiry_dates.size}"
  puts "  Next expiry: #{expiry_dates.first}"

  # Test option picking with real NIFTY spot price
  real_spot = nifty_series.candles.last.close
  puts "  Using real NIFTY spot: ₹#{real_spot.round(2)}"
  pick_result = picker.pick(current_spot: real_spot)

  if pick_result
    puts "  Option picking successful:"
    puts "    Expiry: #{pick_result[:expiry]}"
    puts "    CE SIDs: #{pick_result[:ce_sid].size} strikes"
    puts "    PE SIDs: #{pick_result[:pe_sid].size} strikes"

    # Test getting lot size for a specific option
    if pick_result[:ce_sid].any?
      first_ce_sid = pick_result[:ce_sid].values.first
      lot_size = csv_master.get_lot_size(first_ce_sid)
      puts "    Lot size for first CE: #{lot_size}"
    end
  end

rescue StandardError => e
  puts "✗ CSV Master integration failed: #{e.message}"
  puts e.backtrace.first(3).join("\n")
end

# Test 3: Technical Analysis Integration
puts "\n3. Testing Technical Analysis Integration..."
begin
  # Use real NIFTY data for integration testing
  series = nifty_series.dup # Use a copy for this test

  puts "✓ Using real NIFTY data: #{series.candles.size} candles"

  # Test Holy Grail analysis
  holy_grail = series.holy_grail
  if holy_grail
    puts "  Holy Grail analysis:"
    puts "    Bias: #{holy_grail.bias}"
    puts "    Momentum: #{holy_grail.momentum}"
    puts "    ADX: #{holy_grail.adx.round(2)}"
    puts "    Proceed: #{holy_grail.proceed?}"
  end

  # Test Supertrend analysis
  st_signal = series.supertrend_signal
  puts "  Supertrend signal: #{st_signal}"

  # Test combined signal
  combined_signal = series.combined_signal
  puts "  Combined signal: #{combined_signal}"

rescue StandardError => e
  puts "✗ Technical analysis integration failed: #{e.message}"
  puts e.backtrace.first(3).join("\n")
end

# Test 4: State Management Integration
puts "\n4. Testing State Management Integration..."
begin
  state = DhanScalper::State.new(
    symbols: ["NIFTY"],
    session_target: 1000.0,
    max_day_loss: 1500.0
  )

  puts "✓ State management working"
  puts "  Initial status: #{state.status}"
  puts "  Session target: ₹#{state.session_target}"
  puts "  Max day loss: ₹#{state.max_day_loss}"

  # Test PnL tracking
  state.set_session_pnl(500.0)
  puts "  Session PnL: ₹#{state.pnl}"

  # Test status management
  state.set_status(:paused)
  puts "  Status after pause: #{state.status}"

  state.set_status(:running)
  puts "  Status after resume: #{state.status}"

  # Test subscription management
  state.upsert_idx_sub({
    segment: "IDX_I",
    security_id: "13",
    ltp: 19500.0,
    ts: Time.now.to_i,
    symbol: "NIFTY"
  })

  puts "  Index subscriptions: #{state.subs_idx.size}"

rescue StandardError => e
  puts "✗ State management integration failed: #{e.message}"
  puts e.backtrace.first(3).join("\n")
end

# Test 5: Rate Limiting Integration
puts "\n5. Testing Rate Limiting Integration..."
begin
  rate_limiter = DhanScalper::Services::RateLimiter
  cache = DhanScalper::Services::HistoricalDataCache

  # Test rate limiting with cache
  key = "test_integration"

  # First request should be allowed
  if rate_limiter.can_make_request?(key)
    puts "✓ Rate limiting working"
    puts "  First request: allowed"

    # Record the request
    rate_limiter.record_request(key)

    # Second request should be blocked
    if rate_limiter.can_make_request?(key)
      puts "  Second request: allowed (unexpected)"
    else
      puts "  Second request: blocked (expected)"
      wait_time = rate_limiter.time_until_next_request(key)
      puts "  Wait time: #{wait_time.round(2)} seconds"
    end
  end

  # Test cache integration
  test_data = [{ timestamp: Time.now.to_i, open: 100, high: 105, low: 95, close: 102, volume: 1000 }]
  cache.set("IDX_I", "13", "1", test_data)

  retrieved = cache.get("IDX_I", "13", "1")
  if retrieved
    puts "  Cache integration: working"
    puts "  Cached data: #{retrieved.size} records"
  end

rescue StandardError => e
  puts "✗ Rate limiting integration failed: #{e.message}"
  puts e.backtrace.first(3).join("\n")
end

puts "\n" + "=" * 50
puts "🎯 Integration Testing Completed!"
