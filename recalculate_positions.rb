#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "lib/dhan_scalper"

puts "🔄 Recalculating Existing Positions with Correct PnL"
puts "=" * 60

# Load existing positions from the JSON file
positions_file = "data/paper_positions.json"
if File.exist?(positions_file)
  positions_data = JSON.parse(File.read(positions_file))

  puts "\n📊 Current Positions:"
  puts "-" * 40

  positions_data.each do |key, position|
    puts "\n#{key}:"
    puts "  Symbol: #{position["symbol"]}"
    puts "  Option Type: #{position["option_type"]}"
    puts "  Strike: #{position["strike"]}"
    puts "  Quantity: #{position["quantity"]}"
    puts "  Entry Price: ₹#{position["entry_price"].round(2)}"
    puts "  Current Price: ₹#{position["current_price"].round(2)}"
    puts "  Current PnL: ₹#{position["pnl"].round(2)}"

    # Calculate correct PnL
    entry_price = position["entry_price"]
    current_price = position["current_price"]
    quantity = position["quantity"]
    option_type = position["option_type"]

    correct_pnl = if %w[PE PUT].include?(option_type)
                    # Put options: PnL = (Entry - Current) * Quantity
                    (entry_price - current_price) * quantity
                  else
                    # Call options: PnL = (Current - Entry) * Quantity
                    (current_price - entry_price) * quantity
                  end

    puts "  Correct PnL: ₹#{correct_pnl.round(2)}"
    puts "  Status: #{position["pnl"].round(2) == correct_pnl.round(2) ? "✅ CORRECT" : "❌ NEEDS UPDATE"}"

    # Update the PnL in the data
    position["pnl"] = correct_pnl
  end

  # Save the updated positions
  File.write(positions_file, JSON.pretty_generate(positions_data))
  puts "\n✅ Updated positions saved to #{positions_file}"

else
  puts "❌ Positions file not found: #{positions_file}"
end

# Also check the session report
report_file = "data/reports/PAPER_20250915.json"
if File.exist?(report_file)
  report_data = JSON.parse(File.read(report_file))

  puts "\n📊 Session Report Positions:"
  puts "-" * 40

  if report_data["positions"]
    report_data["positions"].each_with_index do |position, index|
      puts "\nPosition #{index + 1}:"
      puts "  Symbol: #{position["symbol"]}"
      puts "  Option Type: #{position["option_type"]}"
      puts "  Strike: #{position["strike"]}"
      puts "  Quantity: #{position["quantity"]}"
      puts "  Entry Price: ₹#{position["entry_price"].round(2)}"
      puts "  Current Price: ₹#{position["current_price"].round(2)}"
      puts "  Current PnL: ₹#{position["pnl"].round(2)}"

      # Calculate correct PnL
      entry_price = position["entry_price"]
      current_price = position["current_price"]
      quantity = position["quantity"]
      option_type = position["option_type"]

      correct_pnl = if %w[PE PUT].include?(option_type)
                      # Put options: PnL = (Entry - Current) * Quantity
                      (entry_price - current_price) * quantity
                    else
                      # Call options: PnL = (Current - Entry) * Quantity
                      (current_price - entry_price) * quantity
                    end

      puts "  Correct PnL: ₹#{correct_pnl.round(2)}"
      puts "  Status: #{position["pnl"].round(2) == correct_pnl.round(2) ? "✅ CORRECT" : "❌ NEEDS UPDATE"}"

      # Update the PnL in the report data
      position["pnl"] = correct_pnl
    end

    # Update total PnL
    total_pnl = report_data["positions"].sum { |p| p["pnl"] }
    report_data["total_pnl"] = total_pnl

    # Save the updated report
    File.write(report_file, JSON.pretty_generate(report_data))
    puts "\n✅ Updated session report saved to #{report_file}"
    puts "✅ Total PnL updated to: ₹#{total_pnl.round(2)}"
  end
else
  puts "❌ Report file not found: #{report_file}"
end

puts "\n🎯 Summary:"
puts "-" * 60
puts "✅ All positions have been recalculated with correct PnL formulas"
puts "✅ Put options (PE): PnL = (Entry - Current) × Quantity"
puts "✅ Call options (CE): PnL = (Current - Entry) × Quantity"
puts "✅ Files have been updated with correct PnL values"

puts "\n✅ Recalculation completed!"
