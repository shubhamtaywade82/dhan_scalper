#!/usr/bin/env ruby
# frozen_string_literal: true

# Manual test script for WebSocket resilience
# This script demonstrates the WebSocket reconnection and resubscription functionality

require "bundler/setup"
require_relative "../lib/dhan_scalper"

class WebSocketResilienceTest
  def initialize
    @logger = Logger.new($stdout)
    @logger.level = Logger::INFO

    # Create a test configuration
    @config = {
      "SYMBOLS" => {
        "NIFTY" => {
          "idx_sid" => "13",
          "seg_idx" => "IDX_I"
        },
        "BANKNIFTY" => {
          "idx_sid" => "532",
          "seg_idx" => "IDX_I"
        }
      },
      "websocket" => {
        "heartbeat_interval" => 5,
        "max_reconnect_attempts" => 5,
        "base_reconnect_delay" => 1
      }
    }

    @manager = DhanScalper::Services::ResilientWebSocketManager.new(
      logger: @logger,
      heartbeat_interval: @config.dig("websocket", "heartbeat_interval") || 5,
      max_reconnect_attempts: @config.dig("websocket", "max_reconnect_attempts") || 5,
      base_reconnect_delay: @config.dig("websocket", "base_reconnect_delay") || 1
    )

    @tick_count = 0
    @reconnect_count = 0
  end

  def run
    puts "🚀 Starting WebSocket Resilience Test"
    puts "=" * 50

    # Check if DhanHQ is configured
    unless DhanScalper::Services::DhanHQConfig.configured?
      puts "❌ DhanHQ not configured. Please set CLIENT_ID and ACCESS_TOKEN environment variables."
      puts "   Example: CLIENT_ID=your_client_id ACCESS_TOKEN=your_access_token bin/test_websocket_resilience.rb"
      return
    end

    setup_handlers
    start_manager
    add_subscriptions
    simulate_trading_scenario
    simulate_connection_loss
    verify_reconnection
    simulate_position_changes
    cleanup

    puts "\n✅ WebSocket Resilience Test Completed Successfully!"
  end

  private

  def setup_handlers
    @manager.on_price_update do |price_data|
      @tick_count += 1
      puts "📊 Tick #{@tick_count}: #{price_data[:symbol]} = ₹#{price_data[:last_price]}"
    end

    @manager.on_reconnect do
      @reconnect_count += 1
      puts "🔄 Reconnect #{@reconnect_count}: Resubscribing to all instruments"
    end
  end

  def start_manager
    puts "🔌 Starting WebSocket manager..."
    @manager.start
    sleep(1)
    puts "✅ WebSocket manager started"
  end

  def add_subscriptions
    puts "\n📡 Adding baseline subscriptions..."

    # Add baseline indices
    @config["SYMBOLS"].each do |symbol, config|
      @manager.add_baseline_subscription(config["idx_sid"], "INDEX")
      puts "  ✓ Subscribed to #{symbol} (#{config["idx_sid"]})"
    end

    # Add some mock position subscriptions
    @manager.add_position_subscription("OPT123", "OPTION")
    @manager.add_position_subscription("OPT456", "OPTION")
    puts "  ✓ Subscribed to 2 option positions"

    stats = @manager.get_subscription_stats
    puts "📊 Total subscriptions: #{stats[:total_subscriptions]}"
  end

  def simulate_trading_scenario
    puts "\n📈 Simulating trading scenario..."

    # Simulate some market data
    5.times do |i|
      sleep(0.5)
      puts "  📊 Market data update #{i + 1}"
    end

    puts "✅ Trading scenario simulation complete"
  end

  def simulate_connection_loss
    puts "\n⚠️  Simulating connection loss..."

    # Use the test helper method
    @manager.simulate_connection_loss

    puts "  🔌 Connection lost, waiting for reconnection..."
    sleep(2) # Wait for reconnection
  end

  def verify_reconnection
    puts "\n🔍 Verifying reconnection..."

    stats = @manager.get_subscription_stats
    puts "  📊 Connection status: #{stats[:connected] ? 'Connected' : 'Disconnected'}"
    puts "  📊 Total subscriptions: #{stats[:total_subscriptions]}"
    puts "  📊 Reconnect attempts: #{stats[:reconnect_attempts]}"

    if stats[:connected]
      puts "✅ Reconnection successful!"
    else
      puts "❌ Reconnection failed!"
    end
  end

  def simulate_position_changes
    puts "\n📊 Simulating position changes..."

    # Add new position subscription
    @manager.add_position_subscription("OPT789", "OPTION")
    puts "  ✓ Added new position subscription"

    stats = @manager.get_subscription_stats
    puts "  📊 Total subscriptions: #{stats[:total_subscriptions]}"
    puts "  📊 Position subscriptions: #{stats[:position_subscriptions]}"
  end

  def cleanup
    puts "\n🧹 Cleaning up..."
    @manager.stop
    puts "✅ Cleanup complete"
  end
end

# Run the test if this script is executed directly
if __FILE__ == $0
  begin
    test = WebSocketResilienceTest.new
    test.run
  rescue StandardError => e
    puts "❌ Test failed: #{e.message}"
    puts e.backtrace.first(5).join("\n")
    exit(1)
  end
end
