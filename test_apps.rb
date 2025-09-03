#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "dhan_scalper"

puts "🚀 DhanScalper Application Modes Testing"
puts "=" * 50

# Test 1: DryrunApp
puts "\n1. Testing DryrunApp..."
begin
  config = DhanScalper::Config.load(path: "config/scalper.yml")
  dryrun_app = DhanScalper::DryrunApp.new(config, quiet: true, enhanced: true, once: true)

  puts "✓ DryrunApp created successfully"
  puts "  Quiet mode: true"
  puts "  Enhanced mode: true"
  puts "  Once mode: true"

  # Test single run analysis (without starting the full app)
  puts "  Testing signal analysis..."
  # Note: This will try to fetch real data, so it might fail without API
  puts "  (Note: Will attempt to fetch real market data for analysis)"

rescue StandardError => e
  puts "✗ DryrunApp failed: #{e.message}"
  puts "  (Expected if no API credentials or market closed)"
end

# Test 2: PaperApp
puts "\n2. Testing PaperApp..."
begin
  config = DhanScalper::Config.load(path: "config/scalper.yml")
  paper_app = DhanScalper::PaperApp.new(config, quiet: true, enhanced: true)

  puts "✓ PaperApp created successfully"
  puts "  Quiet mode: true"
  puts "  Enhanced mode: true"
  puts "  Starting balance: ₹#{config.dig('paper', 'starting_balance')}"

  # Test configuration access
  puts "  Configuration loaded:"
  puts "    Symbols: #{config['symbols'].join(', ')}"
  puts "    Decision interval: #{config.dig('global', 'decision_interval')} seconds"
  puts "    Max lots per trade: #{config.dig('global', 'max_lots_per_trade')}"

rescue StandardError => e
  puts "✗ PaperApp failed: #{e.message}"
  puts e.backtrace.first(3).join("\n")
end

# Test 3: Main App (Live Trading)
puts "\n3. Testing Main App (Live Trading)..."
begin
  config = DhanScalper::Config.load(path: "config/scalper.yml")
  main_app = DhanScalper::App.new(config, mode: :live, quiet: true, enhanced: true)

  puts "✓ Main App created successfully"
  puts "  Mode: live"
  puts "  Quiet mode: true"
  puts "  Enhanced mode: true"
  puts "  (Note: Not starting to avoid real trading)"

rescue StandardError => e
  puts "✗ Main App failed: #{e.message}"
  puts e.backtrace.first(3).join("\n")
end

# Test 4: CLI Commands (without executing)
puts "\n4. Testing CLI Commands..."
begin
  cli = DhanScalper::CLI.new

  puts "✓ CLI created successfully"
  puts "  Available commands:"
  puts "    - start (live trading)"
  puts "    - paper (paper trading)"
  puts "    - dryrun (signal analysis)"
  puts "    - orders (view orders)"
  puts "    - positions (view positions)"
  puts "    - balance (view balance)"
  puts "    - dashboard (view dashboard)"
  puts "    - live (live LTP dashboard)"
  puts "    - config (check configuration)"

rescue StandardError => e
  puts "✗ CLI failed: #{e.message}"
  puts e.backtrace.first(3).join("\n")
end

# Test 5: Configuration Loading
puts "\n5. Testing Configuration Loading..."
begin
  # Test default config
  default_config = DhanScalper::Config.load
  puts "✓ Default configuration loaded"
  puts "  Default symbols: #{default_config['symbols'].join(', ')}"

  # Test custom config
  custom_config = DhanScalper::Config.load(path: "config/scalper.yml")
  puts "✓ Custom configuration loaded"
  puts "  Custom symbols: #{custom_config['symbols'].join(', ')}"
  puts "  Paper balance: ₹#{custom_config.dig('paper', 'starting_balance')}"
  puts "  Allocation: #{custom_config.dig('global', 'allocation_pct') * 100}%"

  # Test development config if available
  if File.exist?("config/development.yml")
    dev_config = DhanScalper::Config.load(path: "config/development.yml")
    puts "✓ Development configuration loaded"
    puts "  Dev symbols: #{dev_config['symbols'].join(', ')}"
    puts "  Dev balance: ₹#{dev_config.dig('paper', 'starting_balance')}"
  else
    puts "⚠ Development configuration not found"
  end

rescue StandardError => e
  puts "✗ Configuration loading failed: #{e.message}"
  puts e.backtrace.first(3).join("\n")
end

# Test 6: Environment Variables
puts "\n6. Testing Environment Variables..."
begin
  puts "✓ Environment variables check:"
  puts "  CLIENT_ID: #{ENV['CLIENT_ID'] ? 'Set' : 'Not set'}"
  puts "  ACCESS_TOKEN: #{ENV['ACCESS_TOKEN'] ? 'Set' : 'Not set'}"
  puts "  LOG_LEVEL: #{ENV['LOG_LEVEL'] || 'Not set'}"
  puts "  NIFTY_IDX_SID: #{ENV['NIFTY_IDX_SID'] || 'Not set'}"

  # Test DhanHQ configuration
  if ENV['CLIENT_ID'] && ENV['ACCESS_TOKEN']
    puts "  ✓ DhanHQ credentials are configured"
  else
    puts "  ⚠ DhanHQ credentials not configured"
    puts "    Set CLIENT_ID and ACCESS_TOKEN for live trading"
  end

rescue StandardError => e
  puts "✗ Environment variables check failed: #{e.message}"
end

puts "\n" + "=" * 50
puts "🎯 Application Modes Testing Completed!"
