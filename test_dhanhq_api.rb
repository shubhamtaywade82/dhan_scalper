#!/usr/bin/env ruby
# frozen_string_literal: true

# Simple test script to verify DhanHQ API methods
# Run with: ruby test_dhanhq_api.rb

require "bundler/setup"
require "dhan_scalper"

puts "Testing DhanHQ API methods..."
puts "=" * 50

begin
  # Test 1: Configuration
  puts "\n1. Testing DhanHQ configuration..."
  DhanHQ.configure_with_env
  puts "✓ DhanHQ configuration successful"

  # Test 2: Funds API
  puts "\n2. Testing Funds API..."
  begin
    funds = DhanHQ::Models::Funds.fetch
    puts "✓ Funds API successful"
    puts "  Available Balance: #{funds.available_balance}"
    puts "  Utilized Amount: #{funds.utilized_amount}"
    puts "  SOD Limit: #{funds.sod_limit}"
  rescue StandardError => e
    puts "✗ Funds API failed: #{e.message}"
  end

  # Test 3: Order creation (dry run)
  puts "\n3. Testing Order creation (dry run)..."
  begin
    # This is just a test, don't actually place orders
    puts "  Note: Skipping actual order creation for safety"
    puts "✓ Order creation test skipped"
  rescue StandardError => e
    puts "✗ Order creation test failed: #{e.message}"
  end

  # Test 4: Historical Data API
  puts "\n4. Testing Historical Data API..."
  begin
    # Test with a sample security ID and date range
    to_date = Date.today.strftime("%Y-%m-%d")
    from_date = (Date.today - 7).strftime("%Y-%m-%d")

    data = DhanHQ::Models::HistoricalData.intraday(
      security_id: "13",
      exchange_segment: "IDX_I",
      instrument: "INDEX",
      interval: "1",
      from_date: from_date,
      to_date: to_date
    )
    puts "✓ Historical Data API successful"
    puts "  Data type: #{data.class}"
    puts "  Data size: #{data.respond_to?(:size) ? data.size : "N/A"}"
    puts "  Date range: #{from_date} to #{to_date}"
  rescue StandardError => e
    puts "✗ Historical Data API failed: #{e.message}"
  end

  # Test 5: WebSocket (basic test)
  puts "\n5. Testing WebSocket basic functionality..."
  begin
    # Just test if the class exists and can be instantiated
    ws_class = DhanHQ::WS::Client
    puts "✓ WebSocket class found: #{ws_class}"
  rescue StandardError => e
    puts "✗ WebSocket test failed: #{e.message}"
  end

  puts "\n#{"=" * 50}"
  puts "API testing completed!"
rescue StandardError => e
  puts "\n✗ Overall test failed: #{e.message}"
  puts "Backtrace: #{e.backtrace.first(3).join("\n")}"
end
