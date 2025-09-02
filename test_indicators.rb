#!/usr/bin/env ruby
# frozen_string_literal: true

# Test script for the new indicators
# Run with: ruby test_indicators.rb

require "bundler/setup"
require_relative "lib/dhan_scalper"

puts "Testing DhanScalper Indicators..."
puts "=" * 50

begin
  # Test 1: Configuration
  puts "\n1. Testing DhanHQ configuration..."
  DhanHQ.configure_with_env
  puts "✓ DhanHQ configuration successful"

  # Test 2: Load historical data
  puts "\n2. Loading historical data..."
  c1_series = CandleSeries.load_from_dhan_intraday(
    seg: "IDX_I",
    sid: "13",
    interval: "1",
    symbol: "NIFTY_1M"
  )

  c5_series = CandleSeries.load_from_dhan_intraday(
    seg: "IDX_I",
    sid: "13",
    interval: "5",
    symbol: "NIFTY_5M"
  )

  puts "✓ 1M series loaded: #{c1_series.candles.size} candles"
  puts "✓ 5M series loaded: #{c5_series.candles.size} candles"

  # Test 3: Basic indicators
  puts "\n3. Testing basic indicators..."
  if c1_series.candles.size >= 50
    ema20 = c1_series.ema(20)
    ema50 = c1_series.ema(50)
    rsi14 = c1_series.rsi(14)

    puts "✓ EMA(20): #{ema20.last.round(2)}"
    puts "✓ EMA(50): #{ema50.last.round(2)}"
    puts "✓ RSI(14): #{rsi14.last.round(2)}"
  else
    puts "⚠ Not enough data for basic indicators"
  end

  # Test 4: Supertrend
  puts "\n4. Testing Supertrend indicator..."
  if c1_series.candles.size >= 20
    st_values = c1_series.supertrend_new(period: 10, multiplier: 2.0)
    st_signal = c1_series.supertrend_signal(period: 10, multiplier: 2.0)

    puts "✓ Supertrend values: #{st_values.compact.size} valid values"
    puts "✓ Supertrend signal: #{st_signal}"
    puts "✓ Latest Supertrend: #{st_values.compact.last&.round(2)}"
  else
    puts "⚠ Not enough data for Supertrend"
  end

  # Test 5: Holy Grail (if enough data)
  puts "\n5. Testing Holy Grail indicator..."
  if c1_series.candles.size >= 100
    begin
      hg = c1_series.holy_grail
      if hg
        puts "✓ Holy Grail analysis:"
        puts "  - Bias: #{hg.bias}"
        puts "  - Momentum: #{hg.momentum}"
        puts "  - ADX: #{hg.adx.round(2)}"
        puts "  - RSI: #{hg.rsi14.round(2)}"
        puts "  - Proceed: #{hg.proceed?}"
        puts "  - Trend: #{hg.trend}"
      else
        puts "⚠ Holy Grail returned nil"
      end
    rescue StandardError => e
      puts "✗ Holy Grail failed: #{e.message}"
    end
  else
    puts "⚠ Not enough data for Holy Grail (need 100+ candles)"
  end

  # Test 6: Combined signal
  puts "\n6. Testing combined signal..."
  if c1_series.candles.size >= 100
    begin
      signal = c1_series.combined_signal
      puts "✓ Combined signal: #{signal}"
    rescue StandardError => e
      puts "✗ Combined signal failed: #{e.message}"
    end
  else
    puts "⚠ Not enough data for combined signal"
  end

  # Test 7: Enhanced Trend
  puts "\n7. Testing Enhanced Trend..."
  if c1_series.candles.size >= 100 && c5_series.candles.size >= 100
    begin
      trend = DhanScalper::TrendEnhanced.new(seg_idx: "IDX_I", sid_idx: "13")
      decision = trend.decide
      puts "✓ Enhanced Trend decision: #{decision}"
    rescue StandardError => e
      puts "✗ Enhanced Trend failed: #{e.message}"
    end
  else
    puts "⚠ Not enough data for Enhanced Trend"
  end

  puts "\n#{"=" * 50}"
  puts "Indicator testing completed!"
rescue StandardError => e
  puts "\n✗ Overall test failed: #{e.message}"
  puts "Backtrace: #{e.backtrace.first(3).join("\n")}"
end
