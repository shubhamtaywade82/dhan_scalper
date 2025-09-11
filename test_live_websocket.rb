#!/usr/bin/env ruby
# frozen_string_literal: true

puts "Starting live WebSocket test..."

begin
  require "bundler/setup"
  puts "Bundler setup complete"
rescue StandardError => e
  puts "Bundler setup failed: #{e.message}"
  exit 1
end

begin
  require_relative "lib/dhan_scalper"
  puts "DhanScalper loaded successfully"
rescue StandardError => e
  puts "DhanScalper loading failed: #{e.message}"
  puts "Backtrace: #{e.backtrace.first(5)}"
  exit 1
end

puts "🌐 TESTING LIVE WEBSOCKET CONNECTION"
puts "=" * 50

# Set Redis backend
ENV["TICK_CACHE_BACKEND"] = "redis"

# Load configuration
config = DhanScalper::Config.load(path: "config/scalper.yml")
puts "✅ Configuration loaded"

# Test 1: DhanHQ Configuration
puts "\n1️⃣ Testing DhanHQ Configuration..."
begin
  DhanScalper::Services::DhanHQConfig.validate!
  puts "✅ DhanHQ credentials configured"
rescue StandardError => e
  puts "❌ DhanHQ credentials not configured: #{e.message}"
  puts "   This will prevent live data"
  exit 1
end

# Test 2: WebSocket Manager
puts "\n2️⃣ Testing WebSocket Manager..."
ws_manager = DhanScalper::Services::WebSocketManager.new

# Set up price update handler
ws_manager.on_price_update do |price_data|
  puts "📊 Price Update: #{price_data[:symbol]} = ₹#{price_data[:last_price]}"
end

puts "✅ WebSocket manager created with price handler"

# Test 3: Connect to WebSocket
puts "\n3️⃣ Connecting to WebSocket..."
begin
  # Get instruments from config
  instruments = []
  config["SYMBOLS"]&.each do |symbol, symbol_config|
    instruments << {
      instrument_id: symbol_config["idx_sid"],
      instrument_type: "INDEX"
    }
  end

  puts "   Subscribing to instruments: #{instruments.map { |i| i[:instrument_id] }}"

  # Connect with timeout
  ws_manager.connect

  if ws_manager.connected?
    puts "✅ WebSocket connected successfully"

    # Subscribe to instruments
    instruments.each do |instrument|
      ws_manager.subscribe_to_instrument(instrument[:instrument_id], instrument[:instrument_type])
    end

    puts "✅ Subscribed to all instruments"

    # Wait for data
    puts "\n4️⃣ Waiting for live data (30 seconds)..."
    puts "   Press Ctrl+C to stop early"

    start_time = Time.now
    timeout = 30

    while Time.now - start_time < timeout
      # Check if we have any LTP data
      symbols = config["SYMBOLS"]&.keys || []
      symbols.each do |symbol|
        symbol_config = config["SYMBOLS"][symbol]
        ltp = DhanScalper::TickCache.ltp("IDX_I", symbol_config["idx_sid"])
        puts "   #{symbol}: ₹#{ltp}" if ltp && ltp > 0
      end

      sleep 2
    end

    # Final check
    puts "\n5️⃣ Final LTP Check..."
    symbols.each do |symbol|
      symbol_config = config["SYMBOLS"][symbol]
      ltp = DhanScalper::TickCache.ltp("IDX_I", symbol_config["idx_sid"])
      if ltp && ltp > 0
        puts "✅ #{symbol}: ₹#{ltp}"
      else
        puts "❌ #{symbol}: No data"
      end
    end

  else
    puts "❌ WebSocket connection failed"
  end
rescue StandardError => e
  puts "❌ WebSocket error: #{e.message}"
  puts "   This might be due to rate limiting or network issues"
end

# Test 4: LTP Fallback
puts "\n6️⃣ Testing LTP Fallback..."
begin
  ltp_fallback = DhanScalper::Services::LtpFallback.new
  puts "✅ LTP Fallback service created"

  # Test fallback for NIFTY
  nifty_sid = config.dig("SYMBOLS", "NIFTY", "idx_sid")
  if nifty_sid
    ltp = ltp_fallback.get_ltp("IDX_I", nifty_sid)
    if ltp && ltp > 0
      puts "✅ NIFTY LTP from fallback: ₹#{ltp}"
    else
      puts "⚠️  NIFTY LTP fallback returned: #{ltp}"
    end
  end
rescue StandardError => e
  puts "❌ LTP Fallback error: #{e.message}"
end

# Cleanup
puts "\n7️⃣ Cleaning up..."
begin
  ws_manager.disconnect if ws_manager.connected?
  puts "✅ WebSocket disconnected"
rescue StandardError => e
  puts "⚠️  Cleanup error: #{e.message}"
end

puts "\n" + ("=" * 50)
puts "🎯 LIVE WEBSOCKET TEST COMPLETED"
puts "=" * 50
