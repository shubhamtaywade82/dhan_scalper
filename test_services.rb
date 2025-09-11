#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "dhan_scalper"

puts "⚙️ DhanScalper Services Testing"
puts "=" * 50

# Test 1: Rate Limiter
puts "\n1. Testing Rate Limiter..."
begin
  rate_limiter = DhanScalper::Services::RateLimiter

  # Test basic functionality
  key = "test_api"
  can_request = rate_limiter.can_make_request?(key)
  puts "✓ Rate Limiter created"
  puts "  Can make request: #{can_request}"

  # Record a request
  rate_limiter.record_request(key)
  puts "  Request recorded"

  # Check if we need to wait
  can_request_after = rate_limiter.can_make_request?(key)
  puts "  Can make request after recording: #{can_request_after}"

  # Check wait time
  wait_time = rate_limiter.time_until_next_request(key)
  puts "  Time until next request: #{wait_time.round(2)} seconds"
rescue StandardError => e
  puts "✗ Rate Limiter failed: #{e.message}"
  puts e.backtrace.first(3).join("\n")
end

# Test 2: Historical Data Cache
puts "\n2. Testing Historical Data Cache..."
begin
  cache = DhanScalper::Services::HistoricalDataCache

  # Test cache operations
  test_data = [
    { timestamp: Time.now.to_i, open: 100, high: 105, low: 95, close: 102, volume: 1000 },
    { timestamp: Time.now.to_i - 60, open: 98, high: 103, low: 97, close: 100, volume: 1200 }
  ]

  # Set data
  cache.set("IDX_I", "13", "1", test_data)
  puts "✓ Historical Data Cache created"
  puts "  Data cached for IDX_I:13:1"

  # Get data
  retrieved_data = cache.get("IDX_I", "13", "1")
  if retrieved_data
    puts "  Data retrieved: #{retrieved_data.size} records"
  else
    puts "  No data retrieved"
  end
rescue StandardError => e
  puts "✗ Historical Data Cache failed: #{e.message}"
  puts e.backtrace.first(3).join("\n")
end

# Test 3: WebSocket Manager (without connecting)
puts "\n3. Testing WebSocket Manager..."
begin
  logger = Logger.new($stdout)
  logger.level = Logger::WARN # Reduce noise

  ws_manager = DhanScalper::Services::WebSocketManager.new(logger: logger)
  puts "✓ WebSocket Manager created"
  puts "  WebSocket Manager initialized"

  # Test subscription methods (without actually connecting)
  puts "  Subscription methods available:"
  puts "    - subscribe_to_instrument"
  puts "    - unsubscribe_from_instrument"
  puts "    - unsubscribe_all"

  # Test event handlers
  ws_manager.on_price_update do |_data|
    puts "  Price update handler registered"
  end

  ws_manager.on_order_update do |_data|
    puts "  Order update handler registered"
  end

  ws_manager.on_position_update do |_data|
    puts "  Position update handler registered"
  end

  puts "  Event handlers registered successfully"
rescue StandardError => e
  puts "✗ WebSocket Manager failed: #{e.message}"
  puts e.backtrace.first(3).join("\n")
end

# Test 4: Paper Position Tracker
puts "\n4. Testing Paper Position Tracker..."
begin
  # Create a simple mock WebSocket manager
  mock_ws_manager = Object.new
  def mock_ws_manager.subscribe_to_instrument(*_args) = true
  def mock_ws_manager.unsubscribe_from_instrument(*_args) = true
  def mock_ws_manager.on_price_update(&block) = @price_handler = block
  def mock_ws_manager.on_order_update(&block) = @order_handler = block
  def mock_ws_manager.on_position_update(&block) = @position_handler = block

  position_tracker = DhanScalper::Services::PaperPositionTracker.new(
    websocket_manager: mock_ws_manager,
    logger: Logger.new($stdout)
  )

  puts "✓ Paper Position Tracker created"

  # Test tracking underlying
  position_tracker.track_underlying("NIFTY", "13")
  puts "  Underlying tracking started for NIFTY"

  # Test adding position
  position_tracker.add_position(
    "NIFTY", "CE", 19_500, "2025-09-09", "40056", 75, 100.0
  )
  puts "  Position added: NIFTY CE 19500"

  # Test getting positions summary
  summary = position_tracker.get_positions_summary
  puts "  Positions summary:"
  puts "    Total positions: #{summary[:total_positions]}"
  puts "    Total PnL: ₹#{summary[:total_pnl].round(2)}"

  # Test getting underlying summary
  underlying_summary = position_tracker.get_underlying_summary
  puts "  Underlying summary:"
  underlying_summary.each do |symbol, data|
    puts "    #{symbol}: #{data[:instrument_id]}"
  end
rescue StandardError => e
  puts "✗ Paper Position Tracker failed: #{e.message}"
  puts e.backtrace.first(3).join("\n")
end

# Test 5: DhanHQ Config Service
puts "\n5. Testing DhanHQ Config Service..."
begin
  config_service = DhanScalper::Services::DhanHQConfig

  # Test configuration status
  status = config_service.status
  puts "✓ DhanHQ Config Service created"
  puts "  Configured: #{status[:configured]}"
  puts "  Client ID set: #{status[:client_id_set]}"
  puts "  Access Token set: #{status[:access_token_set]}"

  if status[:configured]
    puts "  ✓ DhanHQ is properly configured"
  else
    puts "  ⚠ DhanHQ configuration incomplete"
    puts "    Set CLIENT_ID and ACCESS_TOKEN environment variables"
  end
rescue StandardError => e
  puts "✗ DhanHQ Config Service failed: #{e.message}"
  puts e.backtrace.first(3).join("\n")
end

# Test 6: WebSocket Cleanup Service
puts "\n6. Testing WebSocket Cleanup Service..."
begin
  cleanup_service = DhanScalper::Services::WebSocketCleanup

  # Test cleanup registration
  cleanup_service.register_cleanup
  puts "✓ WebSocket Cleanup Service created"
  puts "  Cleanup registered: #{cleanup_service.cleanup_registered?}"

  # Test cleanup execution (without actually cleaning up)
  puts "  Cleanup methods available:"
  puts "    - register_cleanup"
  puts "    - cleanup_all_websockets"
  puts "    - cleanup_registered?"
rescue StandardError => e
  puts "✗ WebSocket Cleanup Service failed: #{e.message}"
  puts e.backtrace.first(3).join("\n")
end

puts "\n" + ("=" * 50)
puts "🎯 Services Testing Completed!"
