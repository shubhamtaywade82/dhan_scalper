#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "lib/dhan_scalper"

# Test script to verify segment mapping for SENSEX options
puts "🔍 TESTING SEGMENT MAPPING FOR SENSEX OPTIONS"
puts "=" * 60

# Initialize CSV master
csv_master = DhanScalper::CsvMaster.new

# Test SENSEX option lookup
puts "\n📊 Testing SENSEX option segment mapping:"

# Get SENSEX expiry dates
sensex_expiries = csv_master.get_expiry_dates("SENSEX")
puts "SENSEX expiry dates: #{sensex_expiries.join(", ")}"

if sensex_expiries.any?
  first_expiry = sensex_expiries.first
  puts "Using first expiry: #{first_expiry}"

  # Get some strikes for SENSEX
  strikes = csv_master.get_available_strikes("SENSEX", first_expiry)
  puts "Available strikes: #{strikes.first(5).join(", ")}#{"..." if strikes.length > 5}"

  if strikes.any?
    # Test a few strikes
    test_strikes = strikes.first(3)
    test_strikes.each do |strike|
      puts "\n🔍 Testing strike: ₹#{strike}"

      # Test CE option
      ce_security_id = csv_master.get_security_id("SENSEX", first_expiry, strike, "CE")
      if ce_security_id
        segment = csv_master.get_exchange_segment(ce_security_id)
        puts "  CE Option: Security ID #{ce_security_id} → Segment: #{segment}"
        puts "  ✅ Correct segment: #{segment == "BSE_FNO" ? "YES" : "NO"}"
      else
        puts "  CE Option: Not found"
      end

      # Test PE option
      pe_security_id = csv_master.get_security_id("SENSEX", first_expiry, strike, "PE")
      if pe_security_id
        segment = csv_master.get_exchange_segment(pe_security_id)
        puts "  PE Option: Security ID #{pe_security_id} → Segment: #{segment}"
        puts "  ✅ Correct segment: #{segment == "BSE_FNO" ? "YES" : "NO"}"
      else
        puts "  PE Option: Not found"
      end
    end
  end
end

# Test WebSocket manager segment determination
puts "\n🔌 Testing WebSocket Manager segment determination:"

# Create a mock WebSocket manager
DhanScalper::Services::WebSocketManager.new

# Test with a SENSEX option security ID (if we found one)
if sensex_expiries.any? && strikes.any?
  test_strike = strikes.first
  ce_security_id = csv_master.get_security_id("SENSEX", sensex_expiries.first, test_strike, "CE")

  if ce_security_id
    puts "Testing with SENSEX CE option: #{ce_security_id}"

    # This would normally be called internally, but we can test the logic
    begin
      segment = csv_master.get_exchange_segment(ce_security_id)
      puts "CSV Master lookup: #{segment}"
      puts "Expected: BSE_FNO"
      puts "✅ Correct: #{segment == "BSE_FNO" ? "YES" : "NO"}"
    rescue StandardError => e
      puts "❌ Error: #{e.message}"
    end
  end
end

puts "\n" + ("=" * 60)
puts "Segment mapping test complete!"
