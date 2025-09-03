#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "dhan_scalper"

puts "💰 DhanScalper Balance Providers Testing"
puts "=" * 50

# Test 1: PaperWallet
puts "\n1. Testing PaperWallet..."
begin
  wallet = DhanScalper::BalanceProviders::PaperWallet.new(starting_balance: 100_000)
  puts "✓ PaperWallet created successfully"
  puts "  Starting Balance: ₹100,000"
  puts "  Available Balance: ₹#{wallet.available_balance}"
  puts "  Total Balance: ₹#{wallet.total_balance}"
  puts "  Used Balance: ₹#{wallet.used_balance}"

  # Test debit
  wallet.update_balance(10_000, type: :debit)
  puts "  After ₹10,000 debit:"
  puts "    Available: ₹#{wallet.available_balance}"
  puts "    Used: ₹#{wallet.used_balance}"
  puts "    Total: ₹#{wallet.total_balance}"

  # Test credit
  wallet.update_balance(5_000, type: :credit)
  puts "  After ₹5,000 credit:"
  puts "    Available: ₹#{wallet.available_balance}"
  puts "    Used: ₹#{wallet.used_balance}"
  puts "    Total: ₹#{wallet.total_balance}"

  # Test PnL update
  wallet.add_realized_pnl(2_000)
  puts "  After ₹2,000 realized PnL:"
  puts "    Available: ₹#{wallet.available_balance}"
  puts "    Total: ₹#{wallet.total_balance}"

  # Test reset
  wallet.reset_balance(50_000)
  puts "  After reset to ₹50,000:"
  puts "    Available: ₹#{wallet.available_balance}"
  puts "    Total: ₹#{wallet.total_balance}"

rescue StandardError => e
  puts "✗ PaperWallet failed: #{e.message}"
  puts e.backtrace.first(3).join("\n")
end

# Test 2: LiveBalance (without API credentials)
puts "\n2. Testing LiveBalance..."
begin
  live_balance = DhanScalper::BalanceProviders::LiveBalance.new
  puts "✓ LiveBalance created successfully"
  puts "  Available Balance: ₹#{live_balance.available_balance}"
  puts "  Total Balance: ₹#{live_balance.total_balance}"
  puts "  Used Balance: ₹#{live_balance.used_balance}"
  puts "  (Note: Using fallback values since no API credentials)"
rescue StandardError => e
  puts "✗ LiveBalance failed: #{e.message}"
  puts e.backtrace.first(3).join("\n")
end

# Test 3: QuantitySizer
puts "\n3. Testing QuantitySizer..."
begin
  config = DhanScalper::Config.load(path: "config/scalper.yml")
  wallet = DhanScalper::BalanceProviders::PaperWallet.new(starting_balance: 100_000)
  sizer = DhanScalper::QuantitySizer.new(config, wallet)

  puts "✓ QuantitySizer created successfully"

  # Test lot calculation
  lots = sizer.calculate_lots("NIFTY", 100.0)
  puts "  Lots for ₹100 premium: #{lots}"

  quantity = sizer.calculate_quantity("NIFTY", 100.0)
  puts "  Quantity for ₹100 premium: #{quantity}"

  can_afford = sizer.can_afford_position?("NIFTY", 100.0)
  puts "  Can afford ₹100 premium: #{can_afford}"

  # Test with higher premium
  lots_high = sizer.calculate_lots("NIFTY", 1000.0)
  puts "  Lots for ₹1000 premium: #{lots_high}"

rescue StandardError => e
  puts "✗ QuantitySizer failed: #{e.message}"
  puts e.backtrace.first(3).join("\n")
end

puts "\n" + "=" * 50
puts "🎯 Balance Providers Testing Completed!"
