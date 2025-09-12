# frozen_string_literal: true

require "spec_helper"

RSpec.describe "WebSocket Resilience Integration", :integration do
  class FakeWebSocketConnection
    attr_reader :subscriptions, :handlers, :connected, :closed

    def initialize
      @handlers = {}
      @subscriptions = []
      @connected = true
      @closed = false
    end

    def start
      @connected = true
      @closed = false
      self
    end

    def on(event, &block)
      @handlers[event] = block
    end

    def emit_tick(tick_data)
      @handlers[:tick]&.call(tick_data)
    end

    def emit_close(code = 1_000, reason = "Normal closure")
      @handlers[:close]&.call(code, reason)
      @connected = false
      @closed = true
    end

    def emit_error(error)
      @handlers[:error]&.call(error)
      @connected = false
    end

    def subscribe_one(segment:, security_id:)
      @subscriptions << [segment, security_id]
      true
    end

    def unsubscribe_one(segment:, security_id:)
      @subscriptions.delete([segment, security_id])
      true
    end

    def disconnect!
      @connected = false
      @closed = true
    end

    def closed?
      @closed
    end
  end

  let(:logger) { Logger.new(StringIO.new) }
  let(:manager) do
    DhanScalper::Services::ResilientWebSocketManager.new(
      logger: logger,
      heartbeat_interval: 1, # Fast heartbeat for testing
      max_reconnect_attempts: 3,
      base_reconnect_delay: 0.1, # Fast reconnection for testing
    )
  end

  before do
    # Mock DhanHQ configuration
    allow(DhanScalper::Services::DhanHQConfig).to receive(:validate!)
    allow(DhanScalper::Services::DhanHQConfig).to receive(:configure)

    # Mock DhanHQ WebSocket client
    fake_client_class = Class.new do
      def self.new(*)
        @new ||= FakeWebSocketConnection.new
      end
    end
    stub_const("DhanHQ::WS::Client", fake_client_class)
  end

  after do
    manager.stop
  end

  describe "connection and reconnection" do
    it "connects successfully and tracks connection state" do
      manager.start

      expect(manager.connected?).to be true
      expect(manager.reconnect_attempts).to eq(0)
    end

    it "handles connection failures and retries with exponential backoff" do
      # Mock connection failure
      allow(DhanHQ::WS::Client).to receive(:new).and_raise(StandardError, "Connection failed")

      manager.start

      # Should attempt reconnection
      sleep(0.5) # Allow time for reconnection attempts

      expect(manager.reconnect_attempts).to be > 0
    end

    it "stops reconnection after max attempts" do
      # Mock persistent connection failure
      allow(DhanHQ::WS::Client).to receive(:new).and_raise(StandardError, "Connection failed")

      manager.start

      # Wait for all reconnection attempts
      sleep(2)

      expect(manager.reconnect_attempts).to eq(3) # max_reconnect_attempts
      expect(manager.connected?).to be false
    end
  end

  describe "subscription management" do
    it "subscribes to baseline instruments" do
      manager.start

      manager.add_baseline_subscription("13", "INDEX") # NIFTY
      manager.add_baseline_subscription("532", "INDEX") # BANKNIFTY

      stats = manager.get_subscription_stats
      expect(stats[:baseline_subscriptions]).to eq(2)
      expect(stats[:total_subscriptions]).to eq(2)
    end

    it "subscribes to position instruments" do
      manager.start

      manager.add_position_subscription("OPT123", "OPTION")
      manager.add_position_subscription("OPT456", "OPTION")

      stats = manager.get_subscription_stats
      expect(stats[:position_subscriptions]).to eq(2)
      expect(stats[:total_subscriptions]).to eq(2)
    end

    it "tracks subscription types correctly" do
      manager.start

      # Add baseline subscription
      manager.add_baseline_subscription("13", "INDEX")

      # Add position subscription
      manager.add_position_subscription("OPT123", "OPTION")

      stats = manager.get_subscription_stats
      expect(stats[:baseline_subscriptions]).to eq(1)
      expect(stats[:position_subscriptions]).to eq(1)
      expect(stats[:total_subscriptions]).to eq(2)
    end
  end

  describe "resubscription on reconnect" do
    it "resubscribes to all instruments after reconnection" do
      manager.start

      # Add baseline and position subscriptions
      manager.add_baseline_subscription("13", "INDEX")
      manager.add_position_subscription("OPT123", "OPTION")

      # Verify initial subscriptions
      stats = manager.get_subscription_stats
      expect(stats[:total_subscriptions]).to eq(2)

      # Simulate connection loss and reconnection
      manager.instance_variable_get(:@connection).emit_close(1_006, "Abnormal closure")

      # Wait for reconnection
      sleep(0.5)

      # Should have resubscribed
      stats = manager.get_subscription_stats
      expect(stats[:total_subscriptions]).to eq(2)
      expect(stats[:baseline_subscriptions]).to eq(1)
      expect(stats[:position_subscriptions]).to eq(1)
    end

    it "calls resubscription callbacks on reconnect" do
      callback_called = false
      manager.on_reconnect do
        callback_called = true
      end

      manager.start
      manager.add_baseline_subscription("13", "INDEX")

      # Simulate connection loss and reconnection
      manager.instance_variable_get(:@connection).emit_close(1_006, "Abnormal closure")

      # Wait for reconnection
      sleep(0.5)

      expect(callback_called).to be true
    end
  end

  describe "tick deduplication" do
    it "processes new ticks normally" do
      manager.start
      manager.add_baseline_subscription("13", "INDEX")

      tick_received = false
      manager.on_price_update do |_price_data|
        tick_received = true
      end

      # Emit a tick
      current_time = Time.now.to_i
      manager.instance_variable_get(:@connection).emit_tick({
                                                              security_id: "13",
                                                              ltp: 25_000.0,
                                                              ts: current_time,
                                                              symbol: "NIFTY",
                                                            })

      expect(tick_received).to be true
    end

    it "ignores out-of-order ticks" do
      manager.start
      manager.add_baseline_subscription("13", "INDEX")

      tick_count = 0
      manager.on_price_update do |_price_data|
        tick_count += 1
      end

      current_time = Time.now.to_i

      # Emit newer tick first
      manager.instance_variable_get(:@connection).emit_tick({
                                                              security_id: "13",
                                                              ltp: 25_000.0,
                                                              ts: current_time + 10,
                                                              symbol: "NIFTY",
                                                            })

      # Emit older tick (should be ignored)
      manager.instance_variable_get(:@connection).emit_tick({
                                                              security_id: "13",
                                                              ltp: 24_900.0,
                                                              ts: current_time + 5,
                                                              symbol: "NIFTY",
                                                            })

      expect(tick_count).to eq(1)
    end

    it "ignores very old ticks" do
      manager.start
      manager.add_baseline_subscription("13", "INDEX")

      tick_count = 0
      manager.on_price_update do |_price_data|
        tick_count += 1
      end

      # Emit very old tick (beyond deduplication window)
      old_time = Time.now.to_i - 10
      manager.instance_variable_get(:@connection).emit_tick({
                                                              security_id: "13",
                                                              ltp: 25_000.0,
                                                              ts: old_time,
                                                              symbol: "NIFTY",
                                                            })

      # Wait a bit for processing
      sleep(0.1)

      # The tick should be ignored due to being too old
      expect(tick_count).to eq(0)
    end
  end

  describe "heartbeat mechanism" do
    it "sends heartbeats at regular intervals" do
      manager.start

      heartbeat_sent = false

      # Mock the heartbeat check to track when it's called
      allow(manager).to receive(:connected?).and_return(true)
      allow(manager).to receive(:connected?) do
        heartbeat_sent = true
        true
      end

      # Wait for heartbeat
      sleep(1.5)

      expect(heartbeat_sent).to be true
    end

    it "triggers reconnection on heartbeat failure" do
      manager.start

      # Mock heartbeat failure
      allow(manager).to receive(:connected?).and_return(false)

      initial_attempts = manager.reconnect_attempts

      # Wait for heartbeat failure to trigger reconnection
      sleep(2.0)

      expect(manager.reconnect_attempts).to be > initial_attempts
    end
  end

  describe "exponential backoff with jitter" do
    it "calculates increasing delays with jitter" do
      manager.start

      delays = []
      5.times do |i|
        manager.instance_variable_set(:@reconnect_attempts, i + 1)
        delay = manager.send(:calculate_reconnect_delay)
        delays << delay
      end

      # Delays should generally increase (with some jitter)
      expect(delays[1]).to be >= delays[0]
      expect(delays[2]).to be >= delays[1]
      expect(delays[3]).to be >= delays[2]
    end

    it "caps delay at maximum value" do
      manager.start

      # Set high attempt count
      manager.instance_variable_set(:@reconnect_attempts, 20)
      delay = manager.send(:calculate_reconnect_delay)

      expect(delay).to be <= manager.instance_variable_get(:@max_reconnect_delay)
    end
  end

  describe "graceful shutdown" do
    it "stops all threads and disconnects cleanly" do
      manager.start
      manager.add_baseline_subscription("13", "INDEX")

      expect(manager.connected?).to be true

      manager.stop

      expect(manager.connected?).to be false
      expect(manager.instance_variable_get(:@running)).to be false
    end

    it "prevents reconnection after stop" do
      manager.start
      manager.stop

      # Simulate connection loss after stop
      manager.instance_variable_get(:@connection)&.emit_close(1_006, "Abnormal closure")

      # Wait to ensure no reconnection happens
      sleep(0.5)

      expect(manager.connected?).to be false
      expect(manager.instance_variable_get(:@should_reconnect)).to be false
    end
  end

  describe "error handling" do
    it "handles tick processing errors gracefully" do
      manager.start
      manager.add_baseline_subscription("13", "INDEX")

      # Mock error in tick processing
      allow(manager).to receive(:handle_tick_data).and_raise(StandardError, "Tick processing error")

      # Should not crash the application - the error should be caught internally
      manager.instance_variable_get(:@connection).emit_tick({
                                                              security_id: "13",
                                                              ltp: 25_000.0,
                                                              ts: Time.now.to_i,
                                                              symbol: "NIFTY",
                                                            })

      # Wait for error handling
      sleep(0.1)

      # The manager should still be running
      expect(manager.instance_variable_get(:@running)).to be true
    end

    it "handles subscription errors gracefully" do
      manager.start

      # Mock subscription failure
      allow(manager.instance_variable_get(:@connection)).to receive(:subscribe_one).and_raise(StandardError, "Subscription failed")

      result = manager.subscribe_to_instrument("13", "INDEX")

      expect(result).to be false
    end
  end

  describe "integration with position tracking" do
    it "integrates with position tracker for resubscription" do
      # Mock position tracker
      position_tracker = double("PositionTracker")
      allow(position_tracker).to receive(:get_open_positions).and_return([
                                                                           { security_id: "OPT123", symbol: "NIFTY", quantity: 100 },
                                                                           { security_id: "OPT456", symbol: "BANKNIFTY", quantity: 50 },
                                                                         ])

      manager.start

      # Setup resubscription callback to resubscribe to positions
      manager.on_reconnect do
        positions = position_tracker.get_open_positions
        positions.each do |position|
          manager.add_position_subscription(position[:security_id], "OPTION")
        end
      end

      # Simulate connection loss and reconnection
      manager.instance_variable_get(:@connection).emit_close(1_006, "Abnormal closure")

      # Wait for reconnection
      sleep(0.5)

      stats = manager.get_subscription_stats
      expect(stats[:position_subscriptions]).to eq(2)
    end
  end
end
