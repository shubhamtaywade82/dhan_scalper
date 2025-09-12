# frozen_string_literal: true

require "DhanHQ"
require_relative "../tick_cache"
require_relative "dhanhq_config"

module DhanScalper
  module Services
    # Market feed service using DhanHQ WebSocket
    class MarketFeed
      attr_reader :ws_client, :instruments, :running

      def initialize(mode: :quote)
        @mode = mode
        @instruments = []
        @running = false
        @ws_client = nil
        @instrument_segments = {} # Store mapping of security_id -> segment
        setup_cleanup_handlers
      end

      # Start the market feed
      # @param instruments [Array<Hash>] Array of instruments to subscribe to
      # @return [self]
      def start(instruments = [])
        DhanScalper::Services::DhanHQConfig.validate!
        DhanScalper::Services::DhanHQConfig.configure

        @instruments = instruments
        @ws_client = DhanHQ::WS::Client.new(mode: @mode).start
        @running = true

        setup_tick_handler
        subscribe_instruments

        self
      end

      # Stop the market feed
      def stop
        return unless @running

        @running = false
        @ws_client&.disconnect!
        @ws_client = nil
      end

      # Subscribe to additional instruments
      # @param instruments [Array<Hash>] Array of instruments to subscribe to
      def subscribe(instruments)
        instruments.each do |instrument|
          @ws_client.subscribe_one(
            segment: instrument[:segment],
            security_id: instrument[:security_id],
          )
          @instruments << instrument unless @instruments.include?(instrument)
        end
      end

      # Unsubscribe from instruments
      # @param instruments [Array<Hash>] Array of instruments to unsubscribe from
      def unsubscribe(instruments)
        instruments.each do |instrument|
          @ws_client.unsubscribe_one(
            segment: instrument[:segment],
            security_id: instrument[:security_id],
          )
          @instruments.delete(instrument)
        end
      end

      # Get current LTP for an instrument
      # @param segment [String] Exchange segment
      # @param security_id [String] Security ID
      # @return [Float, nil] Current LTP or nil if not available
      def ltp(segment, security_id)
        TickCache.ltp(segment, security_id)
      end

      # Get current tick data for an instrument
      # @param segment [String] Exchange segment
      # @param security_id [String] Security ID
      # @return [Hash, nil] Current tick data or nil if not available
      def tick(segment, security_id)
        TickCache.get(segment, security_id)
      end

      # Get all current tick data
      # @return [Hash] All current tick data
      def all_ticks
        TickCache.all
      end

      # Check if the feed is running
      # @return [Boolean] True if running
      def running?
        @running && @ws_client
      end

      private

      def setup_cleanup_handlers
        # Set up at_exit handler to ensure WebSocket connections are properly closed
        @setup_cleanup_handlers ||= begin
          at_exit do
            stop if @running
          end
          true
        end
      end

      def setup_tick_handler
        @ws_client.on(:tick) do |tick|
          # Enhance tick data with day_high and day_low if not present
          enhanced_tick = tick.dup
          enhanced_tick[:day_high] ||= tick[:high] # Use high as day_high if not provided
          enhanced_tick[:day_low] ||= tick[:low]   # Use low as day_low if not provided

          # Fix segment mapping - the DhanHQ WebSocket client doesn't preserve segment correctly
          # We need to look up the correct segment from our instrument mapping
          correct_segment = find_correct_segment(tick[:security_id])
          enhanced_tick[:segment] = correct_segment if correct_segment

          # Store tick in cache
          TickCache.put(enhanced_tick)

          # Log tick for debugging (can be removed in production)
          if ENV["DHAN_LOG_LEVEL"] == "DEBUG"
            puts "[TICK] #{enhanced_tick[:segment]}:#{tick[:security_id]} LTP=#{tick[:ltp]} H=#{tick[:day_high]} L=#{tick[:day_low]} kind=#{tick[:kind]}"
          end
        end
      end

      def subscribe_instruments
        @instruments.each do |instrument|
          # Store the segment mapping for this instrument
          @instrument_segments[instrument[:security_id]] = instrument[:segment]

          @ws_client.subscribe_one(
            segment: instrument[:segment],
            security_id: instrument[:security_id],
          )
        end
      end

      def find_correct_segment(security_id)
        @instrument_segments[security_id]
      end
    end
  end
end
