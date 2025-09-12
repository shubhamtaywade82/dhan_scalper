#!/usr/bin/env ruby
# frozen_string_literal: true

# Simple End-to-End Smoke Test for Paper Trading
# This script validates the complete paper trading workflow

require "bundler/setup"
require "dotenv/load"
require_relative "../lib/dhan_scalper"

puts "🚀 Starting Simple Paper Trading Smoke Test"
puts "=" * 60

begin
  # Initialize balance provider with 100,000 starting balance
  balance_provider = DhanScalper::BalanceProviders::PaperWallet.new(starting_balance: 100_000.0)
  puts "✅ Balance provider initialized: ₹#{balance_provider.available_balance.round(2)}"

  # Initialize position tracker
  position_tracker = DhanScalper::Services::EnhancedPositionTracker.new
  puts "✅ Position tracker initialized"

  # Initialize equity calculator
  equity_calculator = DhanScalper::Services::EquityCalculator.new(
    balance_provider: balance_provider,
    position_tracker: position_tracker,
    logger: Logger.new($stdout),
  )
  puts "✅ Equity calculator initialized"

  # Initialize paper broker
  broker = DhanScalper::Brokers::PaperBroker.new(
    balance_provider: balance_provider,
    logger: Logger.new($stdout),
  )
  puts "✅ Paper broker initialized"

  # Test BUY order execution
  puts "\n💰 Testing BUY order execution..."
  buy_result = broker.buy_market(
    segment: "NSE_FNO",
    security_id: "TEST123",
    quantity: 75,
    charge_per_order: 20,
  )

  if buy_result.is_a?(DhanScalper::Brokers::Order)
    puts "✅ BUY order executed successfully"
    puts "   Order ID: #{buy_result.id}"
    puts "   Quantity: #{buy_result.qty}"
    puts "   Price: ₹#{buy_result.avg_price}"

    # Verify position was created
    position = position_tracker.get_position(
      exchange_segment: "NSE_FNO",
      security_id: "TEST123",
      side: "LONG",
    )

    if position && position[:net_qty] == 75
      puts "✅ Position created correctly: #{position[:net_qty]} units"
    else
      puts "❌ Position creation failed"
    end

    # Verify balance was debited
    expected_cost = (75 * 100) + 20 # quantity * price + fee
    expected_balance = 100_000 - expected_cost
    actual_balance = balance_provider.available_balance

    if (actual_balance - expected_balance).abs < 0.01
      puts "✅ Balance debited correctly: ₹#{actual_balance.round(2)}"
    else
      puts "❌ Balance debit failed. Expected ₹#{expected_balance}, got ₹#{actual_balance}"
    end
  else
    puts "❌ BUY order execution failed: #{buy_result}"
  end

  # Test SELL order execution
  puts "\n💸 Testing SELL order execution..."
  sell_result = broker.sell_market(
    segment: "NSE_FNO",
    security_id: "TEST123",
    quantity: 75,
    charge_per_order: 20,
  )

  if sell_result.is_a?(DhanScalper::Brokers::Order)
    puts "✅ SELL order executed successfully"
    puts "   Order ID: #{sell_result.id}"
    puts "   Quantity: #{sell_result.qty}"
    puts "   Price: ₹#{sell_result.avg_price}"

    # Verify position was closed
    position = position_tracker.get_position(
      exchange_segment: "NSE_FNO",
      security_id: "TEST123",
      side: "LONG",
    )

    if position.nil? || position[:net_qty] == 0
      puts "✅ Position closed correctly"
    else
      puts "❌ Position closure failed. Net quantity: #{position[:net_qty]}"
    end
  else
    puts "❌ SELL order execution failed: #{sell_result}"
  end

  # Test final balance validation
  puts "\n🏦 Testing final balance validation..."
  final_balance = balance_provider.total_balance
  realized_pnl = balance_provider.realized_pnl
  equity_breakdown = equity_calculator.get_equity_breakdown

  puts "\n📊 Final Results:"
  puts "   Available Balance: ₹#{balance_provider.available_balance.round(2)}"
  puts "   Used Balance: ₹#{balance_provider.used_balance.round(2)}"
  puts "   Total Balance: ₹#{final_balance.round(2)}"
  puts "   Realized PnL: ₹#{realized_pnl.round(2)}"
  puts "   Total Equity: ₹#{equity_breakdown[:total_equity].round(2)}"

  # Expected values
  expected_balance = 101_460.0 # 100,000 + 1,500 profit - 40 fees
  expected_realized_pnl = 1_500.0 # (120 - 100) * 75 - 40 fees

  # Validate final balance
  if (final_balance - expected_balance).abs < 0.01
    puts "✅ Final balance correct: ₹#{final_balance.round(2)}"
  else
    puts "❌ Final balance incorrect. Expected ₹#{expected_balance}, got ₹#{final_balance}"
  end

  # Validate realized PnL
  if (realized_pnl - expected_realized_pnl).abs < 0.01
    puts "✅ Realized PnL correct: ₹#{realized_pnl.round(2)}"
  else
    puts "❌ Realized PnL incorrect. Expected ₹#{expected_realized_pnl}, got ₹#{realized_pnl}"
  end

  puts "\n🎉 Smoke test completed!"
rescue StandardError => e
  puts "❌ Test failed with error: #{e.message}"
  puts e.backtrace.first(5).join("\n")
  exit 1
end
