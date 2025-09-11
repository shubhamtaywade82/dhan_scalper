#!/usr/bin/env ruby
# frozen_string_literal: true

puts "Starting test script..."

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

puts "🧪 COMPREHENSIVE PAPER MODE TEST"
puts "=" * 60

# Test 1: Configuration Loading
puts "\n1️⃣ Testing Configuration Loading..."
begin
  config = DhanScalper::Config.load(path: "config/scalper.yml")
  puts "✅ Config loaded successfully"
  puts "   Symbols: #{config["SYMBOLS"]&.keys}"
  puts "   Mode: #{config["mode"] || "paper"}"
rescue StandardError => e
  puts "❌ Config loading failed: #{e.message}"
  exit 1
end

# Test 2: Redis Connection
puts "\n2️⃣ Testing Redis Connection..."
begin
  redis_store = DhanScalper::Stores::RedisStore.new
  redis_store.connect
  puts "✅ Redis connected successfully"

  # Test basic operations
  redis_store.store_heartbeat
  heartbeat = redis_store.get_heartbeat
  puts "   Heartbeat stored and retrieved: #{heartbeat}"
rescue StandardError => e
  puts "❌ Redis connection failed: #{e.message}"
  exit 1
end

# Test 3: TickCache Backend
puts "\n3️⃣ Testing TickCache Backend..."
begin
  # Set Redis backend
  ENV["TICK_CACHE_BACKEND"] = "redis"

  # Test TickCache
  DhanScalper::TickCache.put({
                               segment: "IDX_I",
                               security_id: "13",
                               ltp: 19_500.0, # Use 'ltp' field name
                               timestamp: Time.now.to_i
                             })

  ltp = DhanScalper::TickCache.ltp("IDX_I", "13")
  puts "✅ TickCache working: LTP = #{ltp}"
rescue StandardError => e
  puts "❌ TickCache failed: #{e.message}"
  puts "   Error details: #{e.backtrace.first(3)}"
end

# Test 4: DhanHQ Configuration
puts "\n4️⃣ Testing DhanHQ Configuration..."
begin
  DhanScalper::Services::DhanHQConfig.validate!
  puts "✅ DhanHQ credentials configured"
rescue StandardError => e
  puts "⚠️  DhanHQ credentials not configured: #{e.message}"
  puts "   This will prevent live data but paper mode should still work"
end

# Test 5: Paper Wallet
puts "\n5️⃣ Testing Paper Wallet..."
begin
  paper_wallet = DhanScalper::BalanceProviders::PaperWallet.new(starting_balance: 100_000)
  puts "✅ Paper wallet created: ₹#{paper_wallet.available_balance}"

  # Test balance operations
  paper_wallet.update_balance(5000, type: :debit)
  puts "   After debit: ₹#{paper_wallet.available_balance}"
rescue StandardError => e
  puts "❌ Paper wallet failed: #{e.message}"
end

# Test 6: Paper Broker
puts "\n6️⃣ Testing Paper Broker..."
begin
  vdm = DhanScalper::VirtualDataManager.new
  paper_broker = DhanScalper::Brokers::PaperBroker.new(
    virtual_data_manager: vdm,
    balance_provider: paper_wallet
  )
  puts "✅ Paper broker created"
rescue StandardError => e
  puts "❌ Paper broker failed: #{e.message}"
end

# Test 7: Position Tracker
puts "\n7️⃣ Testing Position Tracker..."
begin
  position_tracker = DhanScalper::EnhancedPositionTracker.new(mode: :paper)
  puts "✅ Position tracker created"

  # Test position operations
  position_tracker.add_position(
    "NIFTY", "CE", 19_500, "2024-12-12", "TEST123", 75, 100.0
  )
  positions = position_tracker.get_positions
  puts "   Positions count: #{positions.size}"
rescue StandardError => e
  puts "❌ Position tracker failed: #{e.message}"
end

# Test 8: WebSocket Manager (without connecting)
puts "\n8️⃣ Testing WebSocket Manager..."
begin
  ws_manager = DhanScalper::Services::WebSocketManager.new
  puts "✅ WebSocket manager created"
rescue StandardError => e
  puts "❌ WebSocket manager failed: #{e.message}"
end

# Test 9: WebSocket Connection Test
puts "\n9️⃣ Testing WebSocket Connection..."
begin
  # Test WebSocket connection (without actually connecting to avoid rate limits)
  ws_manager = DhanScalper::Services::WebSocketManager.new

  # Test if we can create the connection object
  puts "✅ WebSocket manager ready for connection"
  puts "   Note: Actual connection will be tested in paper mode"
rescue StandardError => e
  puts "❌ WebSocket test failed: #{e.message}"
end

# Test 10: Paper App Initialization
puts "\n🔟 Testing Paper App Initialization..."
begin
  paper_app = DhanScalper::PaperApp.new(config, quiet: true, enhanced: true)
  puts "✅ Paper app created successfully"
rescue StandardError => e
  puts "❌ Paper app creation failed: #{e.message}"
  puts "   Error details: #{e.backtrace.first(5)}"
end

puts "\n" + ("=" * 60)
puts "🎯 COMPREHENSIVE TEST COMPLETED"
puts "=" * 60

# Cleanup
redis_store&.disconnect
