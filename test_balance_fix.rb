#!/usr/bin/env ruby
# frozen_string_literal: true

# Test script to verify balance management fixes
require "bundler/setup"
require "dhan_scalper"

puts "🧪 Testing Balance Management Fixes"
puts "=" * 50

# Test 1: Paper Wallet Initialization
puts "\n1. Testing Paper Wallet Initialization..."
wallet = DhanScalper::BalanceProviders::PaperWallet.new(starting_balance: 200_000)
puts "✓ Initial balance: ₹#{wallet.available_balance}"
puts "✓ Total balance: ₹#{wallet.total_balance}"
puts "✓ Used balance: ₹#{wallet.used_balance}"

# Test 2: Buy Order (Debit)
puts "\n2. Testing Buy Order (Debit)..."
# Simulate buying options worth ₹10,000 + ₹20 charges
total_cost = 10_000 + 20
wallet.update_balance(total_cost, type: :debit)
puts "✓ After buy order:"
puts "  Available: ₹#{wallet.available_balance}"
puts "  Used: ₹#{wallet.used_balance}"
puts "  Total: ₹#{wallet.total_balance}"

# Test 3: Sell Order (Credit) - Profitable Trade
puts "\n3. Testing Sell Order (Credit) - Profitable Trade..."
# Simulate selling for ₹12,000 - ₹20 charges (profit of ₹1,960)
total_proceeds = 12_000 - 20
wallet.update_balance(total_proceeds, type: :credit)
puts "✓ After profitable sell:"
puts "  Available: ₹#{wallet.available_balance}"
puts "  Used: ₹#{wallet.used_balance}"
puts "  Total: ₹#{wallet.total_balance}"

# Test 4: Another Buy Order
puts "\n4. Testing Another Buy Order..."
# Simulate buying options worth ₹5,000 + ₹20 charges
total_cost = 5_000 + 20
wallet.update_balance(total_cost, type: :debit)
puts "✓ After second buy order:"
puts "  Available: ₹#{wallet.available_balance}"
puts "  Used: ₹#{wallet.used_balance}"
puts "  Total: ₹#{wallet.total_balance}"

# Test 5: Sell Order (Credit) - Loss Trade
puts "\n5. Testing Sell Order (Credit) - Loss Trade..."
# Simulate selling for ₹4,000 - ₹20 charges (loss of ₹1,020)
total_proceeds = 4_000 - 20
wallet.update_balance(total_proceeds, type: :credit)
puts "✓ After loss sell:"
puts "  Available: ₹#{wallet.available_balance}"
puts "  Used: ₹#{wallet.used_balance}"
puts "  Total: ₹#{wallet.total_balance}"

# Test 6: Verify Balance Consistency
puts "\n6. Verifying Balance Consistency..."
expected_total = 200_000 + 1_960 - 1_020 # Starting + Profit - Loss
puts "✓ Expected total: ₹#{expected_total}"
puts "✓ Actual total: ₹#{wallet.total_balance}"
puts "✓ Balance consistent: #{wallet.total_balance == expected_total ? "YES" : "NO"}"

puts "\n#{"=" * 50}"
puts "🎯 Balance Management Test Complete!"
puts "The balance should now properly reflect:"
puts "- Used balance shows money tied up in positions"
puts "- Available balance shows money available for new trades"
puts "- Total balance reflects realized P&L from closed positions"
