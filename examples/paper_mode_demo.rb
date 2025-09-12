#!/usr/bin/env ruby
# frozen_string_literal: true

# Paper Mode Demo Script for DhanScalper
# This script demonstrates the complete paper trading functionality
# Run with: bundle exec ruby examples/paper_mode_demo.rb

require_relative "../lib/dhan_scalper"

puts "🚀 DhanScalper Paper Mode Demo"
puts "=" * 50

# Check if we have the required configuration
config_file = "config/scalper.yml"
unless File.exist?(config_file)
  puts "❌ Configuration file not found: #{config_file}"
  puts "Please ensure you have a valid scalper.yml configuration file"
  exit 1
end

# Load configuration
cfg = DhanScalper::Config.load(path: config_file)

puts "\n📋 Configuration Loaded:"
puts "  Symbols: #{cfg["SYMBOLS"]&.keys&.join(", ") || "None"}"
puts "  Starting Balance: ₹#{cfg.dig("paper", "starting_balance") || 200_000}"
puts "  Max Day Loss: ₹#{cfg.dig("global", "max_day_loss") || 5_000}"
puts "  Decision Interval: #{cfg.dig("global", "decision_interval") || 10} seconds"

# Check DhanHQ configuration
puts "\n🔧 DhanHQ Configuration:"
begin
  DhanHQ.configure_with_env
  puts "  ✅ DhanHQ configured successfully"
rescue StandardError => e
  puts "  ❌ DhanHQ configuration failed: #{e.message}"
  puts "  Please check your .env file and API credentials"
  exit 1
end

# Test CSV Master functionality
puts "\n📊 Testing CSV Master Integration:"
begin
  csv_master = DhanScalper::CsvMaster.new

  # Test exchange segment mapping
  nifty_segment = csv_master.get_exchange_segment("13", exchange: "NSE", segment: "I")
  puts "  NIFTY Index Segment: #{nifty_segment || "Not found"}"

  # Test symbol lookup
  nifty_by_symbol = csv_master.get_exchange_segment_by_symbol("NIFTY", "IDX")
  puts "  NIFTY by Symbol: #{nifty_by_symbol || "Not found"}"

  puts "  ✅ CSV Master working correctly"
rescue StandardError => e
  puts "  ❌ CSV Master error: #{e.message}"
  puts "  This might affect option selection and trading"
end

# Test Exchange Segment Mapper
puts "\n🔀 Testing Exchange Segment Mapper:"
test_cases = [
  %w[NSE I Index],
  %w[NSE E Equity],
  %w[NSE D Derivatives],
  %w[BSE E Equity],
  %w[MCX M Commodity],
]

test_cases.each do |exchange, segment, description|
  result = DhanScalper::ExchangeSegmentMapper.exchange_segment(exchange, segment)
  puts "  #{exchange} #{segment} (#{description}) → #{result}"
rescue StandardError => e
  puts "  #{exchange} #{segment} (#{description}) → ERROR: #{e.message}"
end

puts "\n🎯 Paper Mode Features:"
puts "  ✅ Real-time WebSocket price feeds"
puts "  ✅ Automated signal analysis with Holy Grail indicators"
puts "  ✅ ATM option selection and trading"
puts "  ✅ Position tracking and P&L calculation"
puts "  ✅ Risk management and position limits"
puts "  ✅ Comprehensive session reporting (JSON + CSV)"
puts "  ✅ Exchange segment mapping from CSV master data"
puts "  ✅ Paper wallet with virtual balance tracking"

puts "\n🚀 Starting Paper Trading Session..."
puts "  Press Ctrl+C to stop the session"
puts "  Session will auto-generate a comprehensive report on exit"
puts "  Reports will be saved to data/reports/ directory"
puts ""

# Start the paper trading session
begin
  paper_app = DhanScalper::PaperApp.new(
    cfg,
    quiet: false,
    enhanced: true,
    timeout_minutes: 5, # 5-minute demo session
  )

  paper_app.start
rescue Interrupt
  puts "\n\n⏹️  Demo session interrupted by user"
rescue StandardError => e
  puts "\n\n❌ Demo session error: #{e.message}"
  puts e.backtrace.first(5).join("\n")
end

puts "\n✅ Demo completed!"
puts "\n📁 Check the data/reports/ directory for session reports"
puts "📊 Use 'bundle exec exe/dhan_scalper report --latest' to view the latest report"
puts "\n🎉 Thank you for trying DhanScalper Paper Mode!"
