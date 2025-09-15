#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'

puts '🔧 Manual PnL Fix'
puts '=' * 40

# Read the current positions
positions_file = 'data/paper_positions.json'
if File.exist?(positions_file)
  positions_data = JSON.parse(File.read(positions_file))

  puts "\n📊 Current Positions:"
  puts '-' * 30

  positions_data.each do |key, position|
    puts "\n#{key}:"
    puts "  Symbol: #{position['symbol']}"
    puts "  Option Type: #{position['option_type']}"
    puts "  Entry: ₹#{position['entry_price'].round(2)}"
    puts "  Current: ₹#{position['current_price'].round(2)}"
    puts "  Quantity: #{position['quantity']}"
    puts "  Current PnL: ₹#{position['pnl'].round(2)}"

    # Calculate correct PnL
    entry_price = position['entry_price']
    current_price = position['current_price']
    quantity = position['quantity']
    option_type = position['option_type']

    correct_pnl = if option_type == 'PE'
                    # Put options: PnL = (Entry - Current) * Quantity
                    (entry_price - current_price) * quantity
                  else
                    # Call options: PnL = (Current - Entry) * Quantity
                    (current_price - entry_price) * quantity
                  end

    puts "  Correct PnL: ₹#{correct_pnl.round(2)}"
    puts "  Difference: ₹#{(correct_pnl - position['pnl']).round(2)}"

    # Update the PnL
    position['pnl'] = correct_pnl
  end

  # Save updated positions
  File.write(positions_file, JSON.pretty_generate(positions_data))
  puts "\n✅ Positions updated and saved!"

else
  puts '❌ Positions file not found'
end

puts "\n✅ Manual fix completed!"
