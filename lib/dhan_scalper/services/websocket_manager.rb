# frozen_string_literal: true

require "json"
require "logger"
require "set"

module DhanScalper
  module Services
    class WebSocketManager
      attr_reader :connected, :subscribed_instruments, :connection

      def initialize(logger: nil)
        @logger = logger || Logger.new($stdout)
        @connected = false
        @subscribed_instruments = Set.new
        @connection = nil
        @message_handlers = {}
        @reconnect_attempts = 0
        @max_reconnect_attempts = 5
        @reconnect_delay = 5
      end

      def connect
        return if @connected

        @logger.info "[WebSocket] Connecting to DhanHQ WebSocket..."

        begin
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
        return false unless @connected
        return true if @subscribed_instruments.include?(instrument_id)

        @logger.info "[WebSocket] Subscribing to #{instrument_type}: #{instrument_id}"

        begin
          # Determine segment based on instrument type
          segment = case instrument_type
                     when "INDEX" then "IDX_I"
                     when "OPTION" then "NSE_FNO"
                     else "NSE_EQ"
                   end

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
          # For DhanHQ, we need to determine the segment
          # This is a simplified approach - in practice, you'd track segments per instrument
          segments = ["IDX_I", "NSE_FO", "NSE_EQ"]

          segments.each do |segment|
            begin
              @connection.unsubscribe_one(segment: segment, security_id: instrument_id)
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

      private

      def handle_tick_data(tick_data)
        begin
          price_data = {
            instrument_id: tick_data[:security_id],
            symbol: tick_data[:symbol],
            last_price: tick_data[:ltp].to_f,
            open: tick_data[:open].to_f,
            high: tick_data[:high].to_f,
            low: tick_data[:low].to_f,
            close: tick_data[:close].to_f,
            volume: tick_data[:volume].to_i,
            timestamp: tick_data[:ts]
          }

          @message_handlers[:price_update]&.call(price_data)
        rescue StandardError => e
          @logger.error "[WebSocket] Error handling tick data: #{e.message}"
        end
      end


    end
  end
end
