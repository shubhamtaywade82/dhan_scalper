# frozen_string_literal: true

require "json"
require "logger"
require "concurrent"
require "securerandom"

module DhanScalper
  module Services
    # Resilient WebSocket manager with automatic reconnection, heartbeat, and resubscription
    class ResilientWebSocketManager
      attr_reader :connected, :subscribed_instruments, :connection, :reconnect_attempts

      def initialize(logger: nil, heartbeat_interval: 30, max_reconnect_attempts: 10, base_reconnect_delay: 1)
        @logger = logger || Logger.new($stdout)
        @connected = false
        @subscribed_instruments = Set.new
        @instrument_segments = {}
        @connection = nil
        @message_handlers = {}

        # Reconnection settings
        @reconnect_attempts = 0
        @max_reconnect_attempts = max_reconnect_attempts
        @base_reconnect_delay = base_reconnect_delay
        @max_reconnect_delay = 300 # 5 minutes max
        @reconnect_thread = nil
        @should_reconnect = true

        # Heartbeat settings
        @heartbeat_interval = heartbeat_interval
        @heartbeat_thread = nil
        @last_heartbeat = nil
        @heartbeat_timeout = 60 # 1 minute timeout

        # Tick deduplication
        @last_tick_timestamps = Concurrent::Map.new
        @tick_deduplication_window = 5 # seconds

        # Resubscription tracking
        @baseline_subscriptions = Set.new
        @position_subscriptions = Set.new
        @resubscription_callbacks = []

        # Thread safety
        @mutex = Mutex.new
        @running = false
      end

      def connected?
        @connected && @connection && !@connection.closed?
      end

      def start
        return if @running

        @running = true
        @should_reconnect = true
        connect_with_retry
        start_heartbeat
        @logger.info "[ResilientWebSocket] Started with heartbeat interval: #{@heartbeat_interval}s"
      end

      def stop
        @running = false
        @should_reconnect = false

        stop_heartbeat
        stop_reconnect_thread
        disconnect

        @logger.info "[ResilientWebSocket] Stopped"
      end

      def connect_with_retry
        return if @connected && @connection && !@connection.closed?

        @mutex.synchronize do
          return if @connected && @connection && !@connection.closed?

          @logger.info "[ResilientWebSocket] Attempting to connect (attempt #{@reconnect_attempts + 1}/#{@max_reconnect_attempts})"

          begin
            # Configure DhanHQ before connecting
            DhanScalper::Services::DhanHQConfig.validate!
            DhanScalper::Services::DhanHQConfig.configure

            # Disconnect any existing connection first
            disconnect if @connection

            # Create new WebSocket connection
            @connection = DhanHQ::WS::Client.new(mode: :quote).start

            # Setup event handlers
            setup_connection_handlers

            @connected = true
            @reconnect_attempts = 0
            @last_heartbeat = Time.now

            @logger.info "[ResilientWebSocket] Connected successfully"

            # Resubscribe to all instruments
            resubscribe_all
          rescue StandardError => e
            @logger.error "[ResilientWebSocket] Connection failed: #{e.message}"
            @connected = false
            handle_connection_failure
          end
        end
      end

      def disconnect
        return unless @connected

        @logger.info "[ResilientWebSocket] Disconnecting..."

        begin
          # Unsubscribe from all instruments
          unsubscribe_all if @subscribed_instruments.any?

          @connection&.disconnect!
          @connection = nil
          @connected = false
          @subscribed_instruments.clear

          @logger.info "[ResilientWebSocket] Disconnected"
        rescue StandardError => e
          @logger.error "[ResilientWebSocket] Disconnect error: #{e.message}"
        end
      end

      def subscribe_to_instrument(instrument_id, instrument_type = "EQUITY", is_baseline: false, is_position: false)
        # Always store the segment mapping, even if not connected
        @instrument_segments ||= # Determine segment based on instrument type and underlying
          segment = determine_segment(instrument_id, instrument_type)

        # Store the segment mapping for this instrument
        @instrument_segments[instrument_id] = segment

        # Track subscription type for resubscription
        @baseline_subscriptions.add(instrument_id) if is_baseline

        @position_subscriptions.add(instrument_id) if is_position

        return false unless @connected
        return true if @subscribed_instruments.include?(instrument_id)

        @logger.info "[ResilientWebSocket] Subscribing to #{instrument_type}: #{instrument_id}"

        begin
          @connection.subscribe_one(segment: segment, security_id: instrument_id)
          @subscribed_instruments.add(instrument_id)

          @logger.info "[ResilientWebSocket] Subscribed to #{instrument_id} (#{segment})"
          true
        rescue StandardError => e
          @logger.error "[ResilientWebSocket] Subscription failed for #{instrument_id}: #{e.message}"
          false
        end
      end

      def unsubscribe_from_instrument(instrument_id)
        return false unless @connected
        return true unless @subscribed_instruments.include?(instrument_id)

        @logger.info "[ResilientWebSocket] Unsubscribing from: #{instrument_id}"

        begin
          # Get the specific segment for this instrument
          segment = @instrument_segments&.[](instrument_id)

          if segment
            @connection.unsubscribe_one(segment: segment, security_id: instrument_id)
            @instrument_segments.delete(instrument_id)
          else
            # Fallback: try all segments
            segments = %w[IDX_I NSE_FNO NSE_EQ]
            segments.each do |seg|
              @connection.unsubscribe_one(segment: seg, security_id: instrument_id)
            rescue StandardError
              # Ignore errors for segments where the instrument isn't subscribed
            end
          end

          @subscribed_instruments.delete(instrument_id)
          @baseline_subscriptions.delete(instrument_id)
          @position_subscriptions.delete(instrument_id)

          @logger.info "[ResilientWebSocket] Unsubscribed from #{instrument_id}"
          true
        rescue StandardError => e
          @logger.error "[ResilientWebSocket] Unsubscription failed for #{instrument_id}: #{e.message}"
          false
        end
      end

      def unsubscribe_all
        return unless @connected

        @logger.info "[ResilientWebSocket] Unsubscribing from all instruments (#{@subscribed_instruments.size})"

        @subscribed_instruments.dup.each do |instrument_id|
          unsubscribe_from_instrument(instrument_id)
        end

        # Clear segment mappings
        @instrument_segments&.clear
      end

      def on_price_update(&block)
        @message_handlers[:price_update] = block
      end

      def on_order_update(&block)
        @message_handlers[:order_update] = block
      end

      def on_position_update(&block)
        @message_handlers[:position_update] = block
      end

      def on_reconnect(&block)
        @resubscription_callbacks << block
      end

      def add_baseline_subscription(instrument_id, instrument_type = "INDEX")
        @baseline_subscriptions.add(instrument_id)
        subscribe_to_instrument(instrument_id, instrument_type, is_baseline: true)
      end

      def add_position_subscription(instrument_id, instrument_type = "OPTION")
        @position_subscriptions.add(instrument_id)
        subscribe_to_instrument(instrument_id, instrument_type, is_position: true)
      end

      def get_subscription_stats
        {
          connected: @connected,
          total_subscriptions: @subscribed_instruments.size,
          baseline_subscriptions: @baseline_subscriptions.size,
          position_subscriptions: @position_subscriptions.size,
          reconnect_attempts: @reconnect_attempts,
          last_heartbeat: @last_heartbeat,
          heartbeat_timeout: @heartbeat_timeout,
        }
      end

      # Test helper method to simulate connection loss
      def simulate_connection_loss
        return unless @connected && @connection

        @logger.info "[ResilientWebSocket] Simulating connection loss for testing..."

        begin
          @connection.disconnect! if @connection.respond_to?(:disconnect!)
        rescue StandardError => e
          @logger.warn "[ResilientWebSocket] Error during simulated disconnect: #{e.message}"
        end

        # Trigger the connection failure handler
        handle_connection_failure
      end

      private

      def determine_segment(instrument_id, instrument_type)
        case instrument_type
        when "INDEX"
          # For indices, determine based on the instrument ID
          case instrument_id.to_s
          when "13", "25", "51" # NIFTY, BANKNIFTY, SENSEX
          end
          "IDX_I"
        when "OPTION"
          # For options, use CSV master to determine the correct segment
          determine_option_segment(instrument_id)
        else
          "NSE_EQ" # Default for equity
        end
      end

      def determine_option_segment(instrument_id)
        # Use CSV master to get the correct exchange segment
        begin
          @csv_master ||= DhanScalper::CsvMaster.new
          segment = @csv_master.get_exchange_segment(instrument_id)

          if segment
            @logger.debug "[ResilientWebSocket] Found segment #{segment} for option #{instrument_id}"
            return segment
          end
        rescue StandardError => e
          @logger.debug "[ResilientWebSocket] CSV master lookup failed for #{instrument_id}: #{e.message}"
        end

        # Fallback: try to determine based on common patterns
        # BSE options typically have longer IDs and different patterns
        if instrument_id.to_s.length > 4 # BSE options typically have longer IDs
          "BSE_FNO"
        else
          "NSE_FNO" # Default to NSE for most options
        end
      end

      def setup_connection_handlers
        @connection.on(:tick) do |tick_data|
          handle_tick_data(tick_data)
        end

        @connection.on(:close) do |code, reason|
          @logger.warn "[ResilientWebSocket] Connection closed: #{code} - #{reason}"
          @connected = false
          handle_connection_failure
        end

        @connection.on(:error) do |error|
          @logger.error "[ResilientWebSocket] Connection error: #{error}"
          @connected = false
          handle_connection_failure
        end
      end

      def handle_tick_data(tick_data)
        return unless tick_data && tick_data[:security_id]

        instrument_id = tick_data[:security_id]
        segment = @instrument_segments&.[](instrument_id) || "NSE_FNO"
        timestamp = tick_data[:ts] || Time.now.to_i

        # Check for out-of-order ticks
        unless should_process_tick?(instrument_id, timestamp)
          @logger.debug "[ResilientWebSocket] Ignoring out-of-order tick for #{instrument_id}: #{timestamp}"
          return
        end

        # Update last seen timestamp
        @last_tick_timestamps[instrument_id] = timestamp

        # Debug: Log the raw tick data
        @logger.debug "[ResilientWebSocket] Raw tick data: #{tick_data.inspect}" if ENV["DHAN_LOG_LEVEL"] == "DEBUG"

        # Create tick data for TickCache with correct field names
        tick_cache_data = {
          segment: segment,
          security_id: instrument_id,
          ltp: tick_data[:ltp].to_f,
          open: tick_data[:open].to_f,
          high: tick_data[:high].to_f,
          low: tick_data[:low].to_f,
          close: tick_data[:close].to_f,
          volume: tick_data[:volume].to_i,
          timestamp: timestamp,
          day_high: tick_data[:high].to_f,
          day_low: tick_data[:low].to_f,
          atp: tick_data[:ltp].to_f,
          vol: tick_data[:volume].to_i,
        }

        # Store in TickCache
        DhanScalper::TickCache.put(tick_cache_data)

        # Create price data for handlers
        price_data = {
          instrument_id: instrument_id,
          symbol: tick_data[:symbol],
          last_price: tick_data[:ltp].to_f,
          open: tick_data[:open].to_f,
          high: tick_data[:high].to_f,
          low: tick_data[:low].to_f,
          close: tick_data[:close].to_f,
          volume: tick_data[:volume].to_i,
          timestamp: timestamp,
          segment: segment,
          exchange: "NSE",
        }

        @message_handlers[:price_update]&.call(price_data)
      rescue StandardError => e
        @logger.error "[ResilientWebSocket] Error handling tick data: #{e.message}"
      end

      def should_process_tick?(instrument_id, timestamp)
        last_timestamp = @last_tick_timestamps[instrument_id]
        return true unless last_timestamp

        # Ignore ticks older than the last seen timestamp
        return false if timestamp < last_timestamp

        # Ignore ticks that are too old (beyond deduplication window)
        current_time = Time.now.to_i
        return false if (current_time - timestamp) > @tick_deduplication_window

        true
      end

      def handle_connection_failure
        return unless @should_reconnect && @running

        @reconnect_attempts += 1

        if @reconnect_attempts >= @max_reconnect_attempts
          @logger.error "[ResilientWebSocket] Max reconnection attempts reached (#{@max_reconnect_attempts}). Giving up."
          @should_reconnect = false
          return
        end

        delay = calculate_reconnect_delay
        @logger.warn "[ResilientWebSocket] Connection lost. Reconnecting in #{delay}s (attempt #{@reconnect_attempts}/#{@max_reconnect_attempts})"

        start_reconnect_thread(delay)
      end

      def calculate_reconnect_delay
        # Exponential backoff with jitter
        base_delay = @base_reconnect_delay * (2**(@reconnect_attempts - 1))
        jitter = SecureRandom.random_number(base_delay * 0.1) # 10% jitter
        delay = [base_delay + jitter, @max_reconnect_delay].min
        delay.to_i
      end

      def start_reconnect_thread(delay)
        return if @reconnect_thread&.alive?

        @reconnect_thread = Thread.new do
          sleep(delay)
          connect_with_retry if @should_reconnect && @running
        end
      end

      def stop_reconnect_thread
        @reconnect_thread&.kill
        @reconnect_thread = nil
      end

      def start_heartbeat
        return if @heartbeat_thread&.alive?

        @heartbeat_thread = Thread.new do
          while @running
            sleep(@heartbeat_interval)
            next unless @running

            if @connected && @connection && @connection.respond_to?(:closed?) && !@connection.closed?
              @last_heartbeat = Time.now
              @logger.debug "[ResilientWebSocket] Heartbeat sent"
            else
              @logger.warn "[ResilientWebSocket] Heartbeat failed - connection lost"
              @connected = false
              handle_connection_failure
            end
          end
        end
      end

      def stop_heartbeat
        @heartbeat_thread&.kill
        @heartbeat_thread = nil
      end

      def resubscribe_all
        @logger.info "[ResilientWebSocket] Resubscribing to all instruments..."

        # Resubscribe to baseline indices
        @baseline_subscriptions.each do |instrument_id|
          segment = @instrument_segments[instrument_id] || "IDX_I"
          instrument_type = case segment
                            when "IDX_I" then "INDEX"
                            when "NSE_FNO" then "OPTION"
                            else "EQUITY"
                            end

          subscribe_to_instrument(instrument_id, instrument_type, is_baseline: true)
        end

        # Resubscribe to position instruments
        @position_subscriptions.each do |instrument_id|
          segment = @instrument_segments[instrument_id] || "NSE_FNO"
          instrument_type = case segment
                            when "IDX_I" then "INDEX"
                            when "NSE_FNO" then "OPTION"
                            else "EQUITY"
                            end

          subscribe_to_instrument(instrument_id, instrument_type, is_position: true)
        end

        # Call resubscription callbacks
        @resubscription_callbacks.each do |callback|
          callback.call
        rescue StandardError => e
          @logger.error "[ResilientWebSocket] Resubscription callback error: #{e.message}"
        end

        @logger.info "[ResilientWebSocket] Resubscription complete. Total: #{@subscribed_instruments.size} instruments"
      end
    end
  end
end
