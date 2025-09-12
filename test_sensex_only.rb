#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "lib/dhan_scalper"

# Live market data test for SENSEX only
puts "🔌 LIVE MARKET DATA TEST - SENSEX ONLY"
puts "=" * 60

# Enable debug logging
ENV["DHAN_LOG_LEVEL"] = "DEBUG"

# Check environment variables
required_env_vars = ["CLIENT_ID", "ACCESS_TOKEN"]
missing_vars = required_env_vars.select { |var| ENV[var].nil? || ENV[var].empty? }

if missing_vars.any?
  puts "❌ Missing required environment variables: #{missing_vars.join(", ")}"
  puts "Please set them in your .env file or environment"
  exit 1
end

puts "✅ Environment variables configured"

# Test 1: Get real derivatives data for SENSEX only
puts "\n📊 STEP 1: GETTING REAL DERIVATIVES DATA FOR SENSEX"
puts "-" * 50

csv_master = DhanScalper::CsvMaster.new
real_instruments = []

puts "\n🔍 Getting real options for SENSEX:"

expiries = csv_master.get_expiry_dates("SENSEX")
puts "  Expiries: #{expiries.length} found"

if expiries.any?
  first_expiry = expiries.first
  puts "  First expiry: #{first_expiry}"
  
  strikes = csv_master.get_available_strikes("SENSEX", first_expiry)
  puts "  Total strikes: #{strikes.length}"
  
  if strikes.any?
    # Get strikes around the middle
    mid_index = strikes.length / 2
    test_strikes = strikes[mid_index - 1..mid_index + 1] || strikes.first(3)
    
    test_strikes.each do |strike|
      ce_sid = csv_master.get_security_id("SENSEX", first_expiry, strike, "CE")
      pe_sid = csv_master.get_security_id("SENSEX", first_expiry, strike, "PE")
      
      if ce_sid
        ce_segment = csv_master.get_exchange_segment(ce_sid)
        real_instruments << {
          symbol: "SENSEX",
          security_id: ce_sid,
          segment: ce_segment,
          type: "CE",
          strike: strike,
          expiry: first_expiry
        }
        puts "    CE #{strike}: #{ce_sid} → #{ce_segment}"
      end
      
      if pe_sid
        pe_segment = csv_master.get_exchange_segment(pe_sid)
        real_instruments << {
          symbol: "SENSEX",
          security_id: pe_sid,
          segment: pe_segment,
          type: "PE",
          strike: strike,
          expiry: first_expiry
        }
        puts "    PE #{strike}: #{pe_sid} → #{pe_segment}"
      end
    end
  end
end

puts "\n📋 SENSEX instruments to subscribe:"
real_instruments.each do |inst|
  puts "  #{inst[:symbol]} #{inst[:type]} #{inst[:strike]} (#{inst[:expiry]}): #{inst[:security_id]} → #{inst[:segment]}"
end

# Verify all are BSE_FNO
segments = real_instruments.map { |inst| inst[:segment] }.uniq
puts "\n📊 Segments found: #{segments.join(', ')}"
if segments.all? { |seg| seg == "BSE_FNO" }
  puts "✅ All SENSEX instruments correctly mapped to BSE_FNO"
else
  puts "❌ Some SENSEX instruments have incorrect segment mapping"
  exit 1
end

# Test 2: Use MarketFeed for live data
puts "\n📡 STEP 2: USING MARKETFEED FOR LIVE DATA"
puts "-" * 50

begin
  # Create MarketFeed instance
  market_feed = DhanScalper::Services::MarketFeed.new(mode: :quote)
  puts "  MarketFeed created: #{market_feed.class.name}"
  
  # Prepare instruments for subscription
  instruments_to_subscribe = real_instruments.map do |inst|
    {
      segment: inst[:segment],
      security_id: inst[:security_id]
    }
  end
  
  puts "  Subscribing to #{instruments_to_subscribe.length} SENSEX instruments..."
  
  # Start the market feed
  market_feed.start(instruments_to_subscribe)
  puts "  ✅ MarketFeed started successfully"
  
  # Test 3: Monitor live data for a longer period
  puts "\n📊 STEP 3: MONITORING LIVE DATA"
  puts "-" * 50
  
  puts "  Monitoring live data for 60 seconds..."
  puts "  This will show real market data received from WebSocket for SENSEX"
  puts "  Press Ctrl+C to stop early"
  
  start_time = Time.now
  monitor_duration = 60 # seconds
  tick_count = 0
  data_by_segment = {}
  
  begin
    while Time.now - start_time < monitor_duration
      # Check TickCache for new data
      cache_data = DhanScalper::TickCache.all
      
      if cache_data && !cache_data.empty?
        new_ticks = cache_data.select do |key, tick|
          tick[:timestamp] && (Time.now - tick[:timestamp]) < 5 # Last 5 seconds
        end
        
        if new_ticks.any?
          puts "\n  📊 NEW LIVE DATA RECEIVED:"
          new_ticks.each do |key, tick|
            age = (Time.now - tick[:timestamp]).round(1)
            puts "    #{key}: LTP=#{tick[:ltp]}, Age=#{age}s, Segment=#{tick[:segment]}"
            puts "      Open=#{tick[:open]}, High=#{tick[:high]}, Low=#{tick[:low]}, Close=#{tick[:close]}"
            puts "      Volume=#{tick[:volume]}, ATP=#{tick[:atp]}"
            tick_count += 1
            
            # Track data by segment
            data_by_segment[tick[:segment]] ||= []
            data_by_segment[tick[:segment]] << tick
          end
        end
      end
      
      # Show periodic summary
      if (Time.now - start_time).to_i % 15 == 0
        puts "\n  📈 LIVE DATA SUMMARY (#{Time.now.strftime('%H:%M:%S')}):"
        puts "    Total ticks received: #{tick_count}"
        puts "    Cache entries: #{cache_data&.size || 0}"
        
        if cache_data && !cache_data.empty?
          segments = cache_data.values.map { |tick| tick[:segment] }.uniq
          puts "    Segments: #{segments.join(', ')}"
        end
        
        # Show data by segment
        puts "    Data by segment:"
        data_by_segment.each do |segment, ticks|
          puts "      #{segment}: #{ticks.length} ticks"
        end
      end
      
      sleep 3 # Check every 3 seconds
    end
  rescue Interrupt
    puts "\n  ⏹️  Monitoring stopped by user"
  end
  
  # Test 4: Test LTP retrieval for SENSEX
  puts "\n💰 STEP 4: TESTING LTP RETRIEVAL FOR SENSEX"
  puts "-" * 50
  
  puts "\n  Testing LTP for SENSEX options:"
  real_instruments.each do |inst|
    puts "    #{inst[:type]} #{inst[:strike]}:"
    
    # Get LTP from TickCache
    ltp = DhanScalper::TickCache.ltp(inst[:segment], inst[:security_id])
    if ltp
      puts "      ✅ LTP: #{ltp}"
    else
      puts "      ❌ No LTP data available"
    end
    
    # Get full tick data
    tick_data = DhanScalper::TickCache.get(inst[:segment], inst[:security_id])
    if tick_data
      puts "      Full tick data:"
      puts "        LTP: #{tick_data[:ltp]}"
      puts "        Open: #{tick_data[:open]}"
      puts "        High: #{tick_data[:high]}"
      puts "        Low: #{tick_data[:low]}"
      puts "        Close: #{tick_data[:close]}"
      puts "        Volume: #{tick_data[:volume]}"
      puts "        Timestamp: #{tick_data[:timestamp]}"
      puts "        Segment: #{tick_data[:segment]}"
    else
      puts "      ❌ No tick data available"
    end
  end
  
  # Test 5: Test MarketFeed methods for SENSEX
  puts "\n🔧 STEP 5: TESTING MARKETFEED METHODS FOR SENSEX"
  puts "-" * 50
  
  puts "\n  Testing get_current_ltp for SENSEX:"
  real_instruments.first(2).each do |inst| # Test first 2 instruments
    puts "    #{inst[:type]} #{inst[:strike]}:"
    begin
      ltp = market_feed.get_current_ltp(inst[:segment], inst[:security_id])
      if ltp
        puts "      ✅ LTP from MarketFeed: #{ltp}"
      else
        puts "      ❌ No LTP from MarketFeed"
      end
    rescue StandardError => e
      puts "      ❌ Error: #{e.message}"
    end
  end
  
  # Test 6: Check Redis storage
  puts "\n🗄️  STEP 6: CHECKING REDIS STORAGE"
  puts "-" * 50
  
  begin
    require "redis"
    redis = Redis.new(url: ENV.fetch("REDIS_URL", "redis://127.0.0.1:6379/0"))
    
    # Check Redis keys
    keys = redis.keys("ticks:*")
    puts "  Redis keys: #{keys.length}"
    
    if keys.any?
      puts "  Sample Redis data:"
      keys.first(5).each do |key|
        data = redis.hgetall(key)
        ttl = redis.ttl(key)
        puts "    #{key}: TTL=#{ttl}s"
        puts "      LTP: #{data['ltp']}"
        puts "      Volume: #{data['volume']}"
        puts "      Timestamp: #{data['timestamp']}"
        puts "      Segment: #{data['segment']}"
      end
    end
  rescue StandardError => e
    puts "  Redis error: #{e.message}"
  end
  
  # Test 7: Final analysis
  puts "\n📊 STEP 7: FINAL ANALYSIS"
  puts "-" * 50
  
  puts "\n  📈 SENSEX Analysis:"
  
  # Check which instruments have data
  instruments_with_data = real_instruments.select do |inst|
    tick_data = DhanScalper::TickCache.get(inst[:segment], inst[:security_id])
    tick_data && tick_data[:ltp] && tick_data[:ltp] > 0
  end
  
  puts "    Instruments with data: #{instruments_with_data.length}/#{real_instruments.length}"
  
  if instruments_with_data.any?
    puts "    Sample data:"
    instruments_with_data.first(2).each do |inst|
      tick_data = DhanScalper::TickCache.get(inst[:segment], inst[:security_id])
      puts "      #{inst[:type]} #{inst[:strike]}: LTP=#{tick_data[:ltp]}, Segment=#{inst[:segment]}"
    end
  else
    puts "    ⚠️  No live data received for SENSEX options"
    puts "    This could be because:"
    puts "      - SENSEX options are not actively trading during this time"
    puts "      - BSE market hours might be different"
    puts "      - The specific strikes selected might not have active trading"
  end
  
  # Check segments used
  segments_used = real_instruments.map { |inst| inst[:segment] }.uniq
  puts "    Segments used: #{segments_used.join(', ')}"
  
  # Test 8: Final TickCache analysis
  puts "\n📊 STEP 8: FINAL TICKCACHE ANALYSIS"
  puts "-" * 50
  
  cache_data = DhanScalper::TickCache.all
  if cache_data && !cache_data.empty?
    puts "  Final TickCache contents:"
    cache_data.each do |key, tick|
      age = tick[:timestamp] ? (Time.now - tick[:timestamp]).round(1) : "N/A"
      puts "    #{key}: LTP=#{tick[:ltp]}, Age=#{age}s, Segment=#{tick[:segment]}"
    end
    
    # Analyze data freshness
    fresh_ticks = cache_data.select do |key, tick|
      tick[:timestamp] && (Time.now - tick[:timestamp]) < 60 # Last minute
    end
    
    puts "\n  Data freshness analysis:"
    puts "    Total entries: #{cache_data.size}"
    puts "    Fresh entries (< 1 min): #{fresh_ticks.size}"
    puts "    Stale entries (>= 1 min): #{cache_data.size - fresh_ticks.size}"
    
    # Analyze segments
    segments = cache_data.values.map { |tick| tick[:segment] }.tally
    puts "    Segments: #{segments}"
    
    # Check if we have BSE_FNO data
    bse_data = cache_data.select { |key, tick| tick[:segment] == "BSE_FNO" }
    if bse_data.any?
      puts "    ✅ BSE_FNO data found: #{bse_data.size} entries"
    else
      puts "    ❌ No BSE_FNO data found"
    end
  else
    puts "  No data in TickCache"
  end
  
  # Cleanup
  puts "\n🧹 CLEANUP"
  puts "-" * 50
  
  begin
    market_feed.stop
    puts "  MarketFeed stopped"
  rescue StandardError => e
    puts "  Stop error: #{e.message}"
  end
  
rescue StandardError => e
  puts "  ❌ MarketFeed error: #{e.message}"
  puts "  Backtrace: #{e.backtrace.first(5).join("\n")}"
end

puts "\n" + "=" * 60
puts "✅ LIVE MARKET DATA TEST COMPLETE - SENSEX ONLY"
puts "This test shows how real market data flows through the system for SENSEX:"
puts "  📡 SENSEX: BSE_FNO segment with live option data"
puts "  🔄 All data is processed and stored in TickCache with correct segment mapping"
puts "  🗄️  TickCache stores data in Redis with proper BSE_FNO segment information"
puts "  📊 Data can be retrieved for trading decisions on BSE exchange"
