# frozen_string_literal: true

require "DhanHQ"
require_relative "../tick_cache"
require_relative "dhanhq_config"
require_relative "../support/tick_normalizer"

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
          # Normalize incoming tick to our canonical schema
          normalized = DhanScalper::Support::TickNormalizer.normalize(
            tick,
            segment: find_correct_segment(tick[:security_id]) || tick[:segment],
          )

          TickCache.put(normalized) if normalized

          if ENV["DHAN_LOG_LEVEL"] == "DEBUG" && normalized
            puts "[TICK] #{normalized[:segment]}:#{normalized[:security_id]} LTP=#{normalized[:ltp]} H=#{normalized[:day_high]} L=#{normalized[:day_low]} kind=#{normalized[:kind]}"
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
