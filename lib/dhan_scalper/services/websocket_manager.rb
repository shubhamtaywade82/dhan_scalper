# frozen_string_literal: true

require "json"
require "logger"
require "set"
require "securerandom"

module DhanScalper
  module Services
    class WebSocketManager
      attr_reader :connected, :subscribed_instruments, :connection

      def connected?
        @connected
      end

      def initialize(logger: nil)
        @logger = logger || Logger.new($stdout)
        @connected = false
        @subscribed_instruments = Set.new
        @connection = nil
        @message_handlers = {}
        @reconnect_attempts = 0
        @base_reconnect_delay = 1 # seconds
        @max_reconnect_delay = 30 # seconds
        @heartbeat_interval = 5 # seconds between checks
        @heartbeat_timeout = 10 # seconds without ticks => reconnect
        @monitor_thread = nil
        @last_tick_at = Time.at(0)
        @last_ts_per_instrument = {}
        @baseline_instruments = [] # Array of {id:, type:}
        @active_instruments_provider = nil # -> [[id, type], ...]
      end

      def connect
        return if @connected

        @logger.info "[WebSocket] Connecting to DhanHQ WebSocket..."

        begin
          # Configure DhanHQ before connecting
          DhanScalper::Services::DhanHQConfig.validate!
          DhanScalper::Services::DhanHQConfig.configure

          # Disconnect any existing connection first
          disconnect if @connection

          # Create new WebSocket connection
          @connection = DhanHQ::WS::Client.new(mode: :quote).start

          # Setup event handlers
          @connection.on(:tick) do |tick_data|
            handle_tick_data(tick_data)
          end
          @connected = true
          @reconnect_attempts = 0

          @logger.info "[WebSocket] Connected successfully"
          start_monitor!

          # Resubscribe on fresh connections too (idempotent)
          resubscribe_all
        rescue StandardError => e
          @logger.error "[WebSocket] Connection failed: #{e.message}"
          @connected = false
          raise
        end
      end

      def disconnect
        return unless @connected

        @logger.info "[WebSocket] Disconnecting..."

        begin
          # Unsubscribe from all instruments
          unsubscribe_all if @subscribed_instruments.any?

          @connection&.disconnect!
          @connection = nil
          @connected = false
          @subscribed_instruments.clear

          @logger.info "[WebSocket] Disconnected"
        rescue StandardError => e
          @logger.error "[WebSocket] Disconnect error: #{e.message}"
        end
      end

      def subscribe_to_instrument(instrument_id, instrument_type = "EQUITY")
        # Always store the segment mapping, even if not connected
        @instrument_segments ||= {}

        # Determine segment based on instrument type
        segment = case instrument_type
                  when "INDEX" then "IDX_I"
                  when "OPTION" then "NSE_FNO"
                  else "NSE_EQ"
                  end

        # Store the segment mapping for this instrument
        @instrument_segments[instrument_id] = segment

        return false unless @connected
        return true if @subscribed_instruments.include?(instrument_id)

        @logger.info "[WebSocket] Subscribing to #{instrument_type}: #{instrument_id}"

        begin
          @connection.subscribe_one(segment: segment, security_id: instrument_id)
          @subscribed_instruments.add(instrument_id)

          @logger.info "[WebSocket] Subscribed to #{instrument_id} (#{segment})"
          true
        rescue StandardError => e
          @logger.error "[WebSocket] Subscription failed for #{instrument_id}: #{e.message}"
          false
        end
      end

      def unsubscribe_from_instrument(instrument_id)
        return false unless @connected
        return true unless @subscribed_instruments.include?(instrument_id)

        @logger.info "[WebSocket] Unsubscribing from: #{instrument_id}"

        begin
          # Get the specific segment for this instrument
          segment = @instrument_segments&.[](instrument_id)

          if segment
            @connection.unsubscribe_one(segment: segment, security_id: instrument_id)
            @instrument_segments.delete(instrument_id)
          else
            # Fallback: try all segments
            segments = %w[IDX_I NSE_FO NSE_EQ]
            segments.each do |seg|
              @connection.unsubscribe_one(segment: seg, security_id: instrument_id)
            rescue StandardError
              # Ignore errors for segments where the instrument isn't subscribed
            end
          end

          @subscribed_instruments.delete(instrument_id)

          @logger.info "[WebSocket] Unsubscribed from #{instrument_id}"
          true
        rescue StandardError => e
          @logger.error "[WebSocket] Unsubscription failed for #{instrument_id}: #{e.message}"
          false
        end
      end

      def unsubscribe_all
        return unless @connected

        @logger.info "[WebSocket] Unsubscribing from all instruments (#{@subscribed_instruments.size})"

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

      # Configure a static list of baseline instruments (e.g., indices)
      # instruments: Array of [id, type] or hashes {id:, type:}
      def set_baseline_instruments(instruments)
        @baseline_instruments = instruments.map do |it|
          if it.is_a?(Array)
            { id: it[0].to_s, type: it[1] || "EQUITY" }
          else
            { id: it[:id].to_s, type: it[:type] || "EQUITY" }
          end
        end
      end

      # Provide a callable that returns active instruments to resubscribe
      # Block should return Array of [id, type]
      def set_active_instruments_provider(&block)
        @active_instruments_provider = block
      end

      # Force a reconnect and resubscribe (useful for tests/manual)
      def force_reconnect!
        @logger.warn "[WebSocket] Force reconnect requested"
        attempt_reconnect!
      end

      private

      def start_monitor!
        return if @monitor_thread&.alive?

        @monitor_thread = Thread.new do
          Thread.current.abort_on_exception = false
          loop do
            begin
              sleep(@heartbeat_interval)
              # If not connected, try reconnect with backoff
              unless @connected
                attempt_reconnect!
                next
              end

              # Heartbeat: reconnect if ticks stale
              if Time.now - @last_tick_at > @heartbeat_timeout
                @logger.warn "[WebSocket] Heartbeat timeout (#{@heartbeat_timeout}s). Reconnecting..."
                attempt_reconnect!
              end
            rescue StandardError => e
              @logger.error "[WebSocket] Monitor error: #{e.message}"
            end
          end
        end
      end

      def attempt_reconnect!
        # Disconnect stale connection first
        begin
          if @connected
            @connection&.disconnect!
          end
        rescue StandardError
          # ignore
        ensure
          @connected = false
        end

        delay = [@base_reconnect_delay * (2**@reconnect_attempts), @max_reconnect_delay].min
        jitter = rand * (delay * 0.3)
        sleep_time = delay + jitter
        @logger.info "[WebSocket] Reconnecting (attempt #{@reconnect_attempts + 1}) in #{sleep_time.round(2)}s"
        sleep(sleep_time)

        begin
          connect
          @reconnect_attempts = 0
          resubscribe_all
        rescue StandardError => e
          @reconnect_attempts += 1
          @logger.error "[WebSocket] Reconnect failed: #{e.message}"
        end
      end

      def resubscribe_all
        # Baseline indices/instruments
        @baseline_instruments.each do |bi|
          subscribe_to_instrument(bi[:id], bi[:type])
        end

        # Active instruments from provider (e.g., netQty>0)
        if @active_instruments_provider
          begin
            list = Array(@active_instruments_provider.call)
            list.each do |item|
              id, type = item
              subscribe_to_instrument(id.to_s, type || "EQUITY")
            end
          rescue StandardError => e
            @logger.error "[WebSocket] Active instruments provider error: #{e.message}"
          end
        end
      end

      def handle_tick_data(tick_data)
        instrument_id = tick_data[:security_id]
        segment = @instrument_segments&.[](instrument_id) || "NSE_FNO"

        # Ignore out-of-order ticks based on timestamp
        ts = tick_data[:ts] || tick_data[:timestamp]
        if ts
          last_ts = @last_ts_per_instrument[instrument_id]
          if last_ts && (ts < last_ts)
            @logger.debug "[WebSocket] Dropping out-of-order tick for #{instrument_id} (ts=#{ts}, last=#{last_ts})"
            return
          end
          @last_ts_per_instrument[instrument_id] = ts
        end
        @last_tick_at = Time.now

        # Debug: Log the raw tick data
        puts "[DEBUG] Raw tick data: #{tick_data.inspect}" if ENV["DHAN_LOG_LEVEL"] == "DEBUG"

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
          timestamp: tick_data[:ts],
          day_high: tick_data[:high].to_f, # Use high as day_high fallback
          day_low: tick_data[:low].to_f,   # Use low as day_low fallback
          atp: tick_data[:ltp].to_f,       # Use ltp as atp fallback
          vol: tick_data[:volume].to_i
        }

        # Store in TickCache
        DhanScalper::TickCache.put(tick_cache_data)

        # Create price data for handlers (keeping original format for compatibility)
        price_data = {
          instrument_id: instrument_id,
          symbol: tick_data[:symbol],
          last_price: tick_data[:ltp].to_f,
          open: tick_data[:open].to_f,
          high: tick_data[:high].to_f,
          low: tick_data[:low].to_f,
          close: tick_data[:close].to_f,
          volume: tick_data[:volume].to_i,
          timestamp: tick_data[:ts],
          segment: segment,
          exchange: "NSE" # Default to NSE for now
        }

        # Debug: Log the processed price data
        puts "[DEBUG] Processed price data: #{price_data.inspect}" if ENV["DHAN_LOG_LEVEL"] == "DEBUG"

        @message_handlers[:price_update]&.call(price_data)
      rescue StandardError => e
        @logger.error "[WebSocket] Error handling tick data: #{e.message}"
      end
    end
  end
end
