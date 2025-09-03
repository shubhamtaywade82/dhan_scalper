#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "dhan_scalper"

puts "🏦 DhanScalper Brokers Testing"
puts "=" * 50

# Test 1: PaperBroker
puts "\n1. Testing PaperBroker..."
begin
  vdm = DhanScalper::VirtualDataManager.new
  wallet = DhanScalper::BalanceProviders::PaperWallet.new(starting_balance: 100_000)
  broker = DhanScalper::Brokers::PaperBroker.new(
    virtual_data_manager: vdm,
    balance_provider: wallet
  )

  puts "✓ PaperBroker created successfully"
  puts "  Broker name: #{broker.name}"

  # Add some test data to TickCache
  DhanScalper::TickCache.put({
    segment: "NSE_FNO",
    security_id: "CE123",
    ltp: 100.0,
    ts: Time.now.to_i,
    symbol: "NIFTY"
  })

  # Test buy order
  buy_order = broker.buy_market(
    segment: "NSE_FNO",
    security_id: "CE123",
    quantity: 75,
    charge_per_order: 20
  )

  if buy_order
    puts "✓ Buy order placed successfully"
    puts "  Order ID: #{buy_order.id}"
    puts "  Security ID: #{buy_order.security_id}"
    puts "  Side: #{buy_order.side}"
    puts "  Quantity: #{buy_order.qty}"
    puts "  Price: ₹#{buy_order.avg_price}"
    puts "  Total Value: ₹#{buy_order.qty * buy_order.avg_price}"
    puts "  Available Balance: ₹#{wallet.available_balance}"
  else
    puts "✗ Buy order failed"
  end

  # Test sell order
  sell_order = broker.sell_market(
    segment: "NSE_FNO",
    security_id: "CE123",
    quantity: 75,
    charge_per_order: 20
  )

  if sell_order
    puts "✓ Sell order placed successfully"
    puts "  Order ID: #{sell_order.id}"
    puts "  Side: #{sell_order.side}"
  else
    puts "✗ Sell order failed"
  end

  # Test generic place_order method
  place_result = broker.place_order(
    symbol: "NIFTY",
    instrument_id: "PE456",
    side: "BUY",
    quantity: 50,
    price: 80.0,
    order_type: "MARKET"
  )

  if place_result[:success]
    puts "✓ Generic place_order successful"
    puts "  Order ID: #{place_result[:order_id]}"
    puts "  Position created: #{place_result[:position] ? 'Yes' : 'No'}"
  else
    puts "✗ Generic place_order failed: #{place_result[:error]}"
  end

  # Check VDM data
  orders = vdm.get_orders
  positions = vdm.get_positions
  puts "  VDM Orders: #{orders.size}"
  puts "  VDM Positions: #{positions.size}"

rescue StandardError => e
  puts "✗ PaperBroker failed: #{e.message}"
  puts e.backtrace.first(3).join("\n")
end

# Test 2: DhanBroker (without placing real orders)
puts "\n2. Testing DhanBroker..."
begin
  vdm = DhanScalper::VirtualDataManager.new
  wallet = DhanScalper::BalanceProviders::LiveBalance.new
  broker = DhanScalper::Brokers::DhanBroker.new(
    virtual_data_manager: vdm,
    balance_provider: wallet
  )

  puts "✓ DhanBroker created successfully"
  puts "  Broker name: #{broker.name}"
  puts "  (Note: Not placing real orders to avoid charges)"

rescue StandardError => e
  puts "✗ DhanBroker failed: #{e.message}"
  puts e.backtrace.first(3).join("\n")
end

# Test 3: Virtual Data Manager
puts "\n3. Testing Virtual Data Manager..."
begin
  vdm = DhanScalper::VirtualDataManager.new

  # Test order management
  test_order = DhanScalper::Brokers::Order.new("TEST123", "CE789", "BUY", 100, 95.0)
  vdm.add_order(test_order)

  orders = vdm.get_orders
  puts "✓ VDM order management working"
  puts "  Orders count: #{orders.size}"
  puts "  Latest order: #{orders.last[:id]}" if orders.any?

  # Test position management
  test_position = DhanScalper::Position.new(
    security_id: "CE789",
    side: "BUY",
    entry_price: 95.0,
    quantity: 100,
    symbol: "NIFTY",
    current_price: 98.0
  )
  vdm.add_position(test_position)

  positions = vdm.get_positions
  puts "✓ VDM position management working"
  puts "  Positions count: #{positions.size}"
  puts "  Latest position: #{positions.last[:symbol]}" if positions.any?

  # Test balance management
  vdm.set_initial_balance(50_000)
  balance = vdm.get_balance
  puts "✓ VDM balance management working"
  puts "  Balance: ₹#{balance[:available]}"

rescue StandardError => e
  puts "✗ VDM failed: #{e.message}"
  puts e.backtrace.first(3).join("\n")
end

puts "\n" + "=" * 50
puts "🎯 Brokers Testing Completed!"
