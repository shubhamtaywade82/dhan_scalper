#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require_relative "lib/dhan_scalper"

puts "🔍 DEBUGGING TICK CACHE"
puts "=" * 40

# Set Redis backend
ENV["TICK_CACHE_BACKEND"] = "redis"

puts "Backend: #{ENV.fetch("TICK_CACHE_BACKEND", nil)}"

# Test 1: Direct Redis operations
puts "\n1️⃣ Testing Direct Redis Operations..."
redis_store = DhanScalper::Stores::RedisStore.new
redis_store.connect

# Store tick data directly
tick_data = {
  segment: "IDX_I",
  security_id: "13",
  last_price: 19_500.0,
  timestamp: Time.now.to_i,
  day_high: 19_600.0,
  day_low: 19_400.0,
  atp: 19_520.0,
  vol: 1000
}

redis_store.store_tick("IDX_I", "13", tick_data)
puts "✅ Tick data stored directly in Redis"

# Retrieve tick data
retrieved_tick = redis_store.get_tick("IDX_I", "13")
puts "Retrieved tick: #{retrieved_tick}"

# Test 2: TickCache operations
puts "\n2️⃣ Testing TickCache Operations..."

# Store via TickCache
DhanScalper::TickCache.put(tick_data)
puts "✅ Tick data stored via TickCache"

# Retrieve via TickCache
ltp = DhanScalper::TickCache.ltp("IDX_I", "13")
puts "LTP from TickCache: #{ltp}"

# Get full tick
full_tick = DhanScalper::TickCache.get("IDX_I", "13")
puts "Full tick from TickCache: #{full_tick}"

# Test 3: Check Redis keys
puts "\n3️⃣ Checking Redis Keys..."
redis = redis_store.instance_variable_get(:@redis)
keys = redis.keys("dhan_scalper:v1:ticks:*")
puts "Redis keys: #{keys}"

keys.each do |key|
  value = redis.hgetall(key)
  puts "Key: #{key} -> #{value}"
end

# Test 4: Check TickCache stats
puts "\n4️⃣ TickCache Stats..."
stats = DhanScalper::TickCache.stats
puts "TickCache stats: #{stats}"

redis_store.disconnect
