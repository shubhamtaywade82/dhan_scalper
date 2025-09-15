#!/usr/bin/env ruby
# frozen_string_literal: true

# Example script demonstrating exchange segment mapping functionality
# Run with: bundle exec ruby examples/exchange_segment_example.rb

require_relative '../lib/dhan_scalper'

puts '🔍 Exchange Segment Mapping Example'
puts '=' * 50

# Initialize CSV master
csv_master = DhanScalper::CsvMaster.new

puts "\n📊 Direct Exchange Segment Mapping:"
puts '-' * 30

# Test the mapper directly
test_cases = [
  %w[NSE I Index],
  %w[NSE E Equity],
  %w[NSE D Derivatives],
  %w[NSE C Currency],
  %w[BSE I Index],
  %w[BSE E Equity],
  %w[BSE D Derivatives],
  %w[BSE C Currency],
  %w[MCX M Commodity]
]

test_cases.each do |exchange, segment, description|
  result = DhanScalper::ExchangeSegmentMapper.exchange_segment(exchange, segment)
  puts "  #{exchange} #{segment} (#{description}) → #{result}"
rescue ArgumentError => e
  puts "  #{exchange} #{segment} (#{description}) → ERROR: #{e.message}"
end

puts "\n🏢 Real CSV Data Examples:"
puts '-' * 30

# Test with real CSV data
real_examples = [
  { security_id: '13', exchange: 'NSE', segment: 'I', description: 'NIFTY Index' },
  { security_id: '13', exchange: 'NSE', segment: 'C', description: 'NIFTY Currency' },
  { security_id: '500325', exchange: 'BSE', segment: 'E', description: 'RELIANCE BSE Equity' },
  { security_id: '2881', exchange: 'NSE', segment: 'E', description: 'RELIANCE NSE Equity' }
]

real_examples.each do |example|
  result = csv_master.get_exchange_segment(
    example[:security_id],
    exchange: example[:exchange],
    segment: example[:segment]
  )
  puts "  #{example[:description]} (#{example[:security_id]}) → #{result || 'Not found'}"
end

puts "\n🔍 Symbol-based Lookup:"
puts '-' * 30

# Test symbol-based lookup
symbols = %w[NIFTY BANKNIFTY RELIANCE]
symbols.each do |symbol|
  # Try different instrument types
  %w[IDX OPTIDX EQ].each do |instrument|
    result = csv_master.get_exchange_segment_by_symbol(symbol, instrument)
    puts "  #{symbol} #{instrument} → #{result || 'Not found'}"
  end
end

puts "\n📋 Exchange Information:"
puts '-' * 30

# Test exchange info lookup
test_security_ids = %w[13 500325 2881]
test_security_ids.each do |security_id|
  info = csv_master.get_exchange_info(security_id)
  if info
    puts "  Security ID #{security_id}:"
    puts "    Exchange: #{info[:exchange]} (#{info[:exchange_name]})"
    puts "    Segment: #{info[:segment]} (#{info[:segment_name]})"
    puts "    DhanHQ Segment: #{info[:exchange_segment] || 'Unsupported'}"
  else
    puts "  Security ID #{security_id}: Not found"
  end
  puts
end

puts "\n✅ Example completed successfully!"
puts "\n💡 Usage Tips:"
puts '  - Use get_exchange_segment(security_id, exchange:, segment:) for precise lookups'
puts '  - Use get_exchange_segment_by_symbol(symbol, instrument_type) for symbol-based lookups'
puts '  - Use get_exchange_info(security_id) for complete exchange information'
puts '  - The mapper supports NSE, BSE, and MCX exchanges with various segments'
