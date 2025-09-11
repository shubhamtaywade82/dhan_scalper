#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require_relative "lib/dhan_scalper"

puts "🔧 TESTING TICK CACHE FIX"
puts "=" * 40

# Set Redis backend
ENV["TICK_CACHE_BACKEND"] = "redis"

# Test with correct field names
puts "\n1️⃣ Testing with correct field names..."

# Create tick data with 'ltp' field instead of 'last_price'
tick_data = {
  segment: "IDX_I",
  security_id: "13",
  ltp: 19500.0,  # Use 'ltp' instead of 'last_price'
  timestamp: Time.now.to_i,
  day_high: 19600.0,
  day_low: 19400.0,
  atp: 19520.0,
  vol: 1000
}

# Store via TickCache
DhanScalper::TickCache.put(tick_data)
puts "✅ Tick data stored with 'ltp' field"

# Retrieve LTP
ltp = DhanScalper::TickCache.ltp("IDX_I", "13")
puts "LTP retrieved: #{ltp}"

# Test with RedisStore directly
puts "\n2️⃣ Testing with RedisStore directly..."
redis_store = DhanScalper::Stores::RedisStore.new
redis_store.connect

# Store tick data
redis_store.store_tick("IDX_I", "13", tick_data)
puts "✅ Tick data stored via RedisStore"

# Retrieve LTP
ltp_from_redis = redis_store.get_ltp("IDX_I", "13")
puts "LTP from RedisStore: #{ltp_from_redis}"

# Get full tick
full_tick = redis_store.get_tick("IDX_I", "13")
puts "Full tick: #{full_tick}"

redis_store.disconnect

puts "\n✅ TICK CACHE FIX TEST COMPLETED"
