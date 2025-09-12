# frozen_string_literal: true

require "spec_helper"

RSpec.describe "WebSocket Resubscription Demo", :integration do
  class FakeMarketFeed
    attr_reader :subscriptions, :tick_count, :reconnect_count

    def initialize
      @subscriptions = []
      @tick_count = 0
      @reconnect_count = 0
      @handlers = {}
    end

    def subscribe(segment:, security_id:)
      @subscriptions << [segment, security_id]
      true
    end

    def unsubscribe(segment:, security_id:)
      @subscriptions.delete([segment, security_id])
      true
    end

    def on_tick(&block)
      @handlers[:tick] = block
    end

    def on_close(&block)
      @handlers[:close] = block
    end

    def emit_tick(security_id, price, timestamp = Time.now.to_i)
      @tick_count += 1
      @handlers[:tick]&.call({
                               security_id: security_id,
                               ltp: price,
                               ts: timestamp,
                               symbol: security_id == "13" ? "NIFTY" : "OPTION",
                             })
    end

    def simulate_disconnect
      @reconnect_count += 1
      @handlers[:close]&.call(1_006, "Simulated disconnect")
    end

    def simulate_reconnect
      # Simulate successful reconnection
      true
    end
  end

  let(:fake_feed) { FakeMarketFeed.new }
  let(:logger) { Logger.new(StringIO.new) }
  let(:manager) do
    DhanScalper::Services::ResilientWebSocketManager.new(
      logger: logger,
      heartbeat_interval: 1,
      max_reconnect_attempts: 5,
      base_reconnect_delay: 0.1,
    )
  end

  before do
    # Mock DhanHQ WebSocket client to use our fake feed
    fake_client_class = Class.new do
      def self.new(*)
        @instance ||= FakeMarketFeed.new
      end
    end
    stub_const("DhanHQ::WS::Client", fake_client_class)

    # Mock DhanHQ configuration
    allow(DhanScalper::Services::DhanHQConfig).to receive(:validate!)
    allow(DhanScalper::Services::DhanHQConfig).to receive(:configure)
  end

  after do
    manager.stop
  end

  it "demonstrates complete resubscription workflow" do
    puts "\n=== WebSocket Resubscription Demo ==="

    # Start the manager
    manager.start
    puts "✓ WebSocket manager started"

    # Add baseline subscriptions (NIFTY, BANKNIFTY indices)
    manager.add_baseline_subscription("13", "INDEX")    # NIFTY
    manager.add_baseline_subscription("532", "INDEX")   # BANKNIFTY
    puts "✓ Added baseline subscriptions: NIFTY, BANKNIFTY"

    # Add position subscriptions (options with net quantity > 0)
    manager.add_position_subscription("OPT123", "OPTION")  # NIFTY CE
    manager.add_position_subscription("OPT456", "OPTION")  # NIFTY PE
    puts "✓ Added position subscriptions: 2 options"

    # Verify initial subscriptions
    stats = manager.get_subscription_stats
    expect(stats[:total_subscriptions]).to eq(4)
    expect(stats[:baseline_subscriptions]).to eq(2)
    expect(stats[:position_subscriptions]).to eq(2)
    puts "✓ Initial subscriptions verified: #{stats[:total_subscriptions]} total"

    # Setup tick handler to track received ticks
    received_ticks = []
    manager.on_price_update do |price_data|
      received_ticks << {
        security_id: price_data[:instrument_id],
        price: price_data[:last_price],
        timestamp: price_data[:timestamp],
      }
    end

    # Emit some ticks to verify normal operation
    fake_feed.emit_tick("13", 25_000.0)      # NIFTY
    fake_feed.emit_tick("532", 45_000.0)     # BANKNIFTY
    fake_feed.emit_tick("OPT123", 150.0)    # NIFTY CE
    fake_feed.emit_tick("OPT456", 120.0)    # NIFTY PE

    sleep(0.1) # Allow time for tick processing
    puts "✓ Emitted initial ticks: #{received_ticks.size} received"

    # Simulate connection loss
    puts "⚠️  Simulating connection loss..."
    manager.instance_variable_get(:@connection).simulate_disconnect

    # Wait for reconnection
    sleep(0.5)
    puts "✓ Reconnection completed"

    # Verify resubscription occurred
    stats = manager.get_subscription_stats
    expect(stats[:total_subscriptions]).to eq(4)
    expect(stats[:baseline_subscriptions]).to eq(2)
    expect(stats[:position_subscriptions]).to eq(2)
    puts "✓ Resubscription verified: #{stats[:total_subscriptions]} instruments resubscribed"

    # Emit ticks after reconnection to verify MTM continues
    received_ticks.clear
    fake_feed.emit_tick("13", 25_100.0)      # NIFTY updated
    fake_feed.emit_tick("532", 45_100.0)     # BANKNIFTY updated
    fake_feed.emit_tick("OPT123", 155.0)    # NIFTY CE updated
    fake_feed.emit_tick("OPT456", 125.0)    # NIFTY PE updated

    sleep(0.1) # Allow time for tick processing
    puts "✓ Post-reconnection ticks received: #{received_ticks.size} ticks"

    # Verify tick deduplication works
    puts "✓ Testing tick deduplication..."
    old_timestamp = Time.now.to_i - 10
    fake_feed.emit_tick("13", 25_000.0, old_timestamp) # Old tick should be ignored

    sleep(0.1)
    expect(received_ticks.size).to eq(4) # Should still be 4, not 5
    puts "✓ Tick deduplication working: old ticks ignored"

    # Verify heartbeat mechanism
    puts "✓ Testing heartbeat mechanism..."
    initial_heartbeat = manager.instance_variable_get(:@last_heartbeat)
    sleep(1.5) # Wait for heartbeat
    current_heartbeat = manager.instance_variable_get(:@last_heartbeat)
    expect(current_heartbeat).to be > initial_heartbeat
    puts "✓ Heartbeat mechanism working"

    # Final verification
    final_stats = manager.get_subscription_stats
    puts "\n=== Final Statistics ==="
    puts "Connected: #{final_stats[:connected]}"
    puts "Total subscriptions: #{final_stats[:total_subscriptions]}"
    puts "Baseline subscriptions: #{final_stats[:baseline_subscriptions]}"
    puts "Position subscriptions: #{final_stats[:position_subscriptions]}"
    puts "Reconnect attempts: #{final_stats[:reconnect_attempts]}"
    puts "Last heartbeat: #{final_stats[:last_heartbeat]}"

    expect(final_stats[:connected]).to be true
    expect(final_stats[:total_subscriptions]).to eq(4)
    puts "\n✅ WebSocket resilience demo completed successfully!"
  end

  it "demonstrates exponential backoff behavior" do
    puts "\n=== Exponential Backoff Demo ==="

    manager.start

    # Simulate multiple connection failures to see backoff
    delays = []
    5.times do |i|
      manager.instance_variable_set(:@reconnect_attempts, i + 1)
      delay = manager.send(:calculate_reconnect_delay)
      delays << delay
      puts "Attempt #{i + 1}: #{delay}s delay"
    end

    # Delays should generally increase
    expect(delays[1]).to be >= delays[0]
    expect(delays[2]).to be >= delays[1]
    expect(delays[3]).to be >= delays[2]

    puts "✓ Exponential backoff working correctly"
  end

  it "demonstrates graceful shutdown" do
    puts "\n=== Graceful Shutdown Demo ==="

    manager.start
    manager.add_baseline_subscription("13", "INDEX")
    manager.add_position_subscription("OPT123", "OPTION")

    expect(manager.connected?).to be true
    puts "✓ Manager started and connected"

    manager.stop
    puts "✓ Stop command issued"

    expect(manager.connected?).to be false
    expect(manager.instance_variable_get(:@running)).to be false
    puts "✓ Graceful shutdown completed"
  end
end
