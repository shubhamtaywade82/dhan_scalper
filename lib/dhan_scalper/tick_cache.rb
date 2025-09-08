# frozen_string_literal: true

require "concurrent"

module DhanScalper
  class TickCache
    MAP = Concurrent::Map.new

    class << self
      # Store a tick in the cache
      # @param tick [Hash] The tick data with keys like :segment, :security_id, :ltp, etc.
      def put(tick)
        return unless tick.is_a?(Hash) && tick[:segment] && tick[:security_id]

        key = "#{tick[:segment]}:#{tick[:security_id]}"
        MAP[key] = tick.merge(timestamp: Time.now)
      end

      # Get a tick from the cache
      # @param segment [String] Exchange segment (e.g., "NSE_FNO", "IDX_I")
      # @param security_id [String] Security ID
      # @return [Hash, nil] The tick data or nil if not found
      def get(segment, security_id)
        key = "#{segment}:#{security_id}"
        MAP[key]
      end

      # Get the LTP (Last Traded Price) for a specific instrument
      # @param segment [String] Exchange segment
      # @param security_id [String] Security ID
      # @return [Float, nil] The LTP or nil if not found
      def ltp(segment, security_id)
        tick = get(segment, security_id)
        tick&.dig(:ltp)
      end

      # Get all cached ticks
      # @return [Hash] All cached ticks
      def all
        result = {}
        MAP.each { |key, value| result[key] = value }
        result
      end

      # Clear all cached data
      def clear
        MAP.clear
      end

      # Get tick data for multiple instruments
      # @param instruments [Array<Hash>] Array of hashes with :segment and :security_id
      # @return [Hash] Hash with instrument keys and their tick data
      def get_multiple(instruments)
        result = {}
        instruments.each do |instrument|
          segment = instrument[:segment]
          security_id = instrument[:security_id]
          key = "#{instrument[:name] || "#{segment}:#{security_id}"}"
          result[key] = get(segment, security_id)
        end
        result
      end

      # Check if a tick is fresh (within the last 30 seconds)
      # @param segment [String] Exchange segment
      # @param security_id [String] Security ID
      # @param max_age [Integer] Maximum age in seconds (default: 30)
      # @return [Boolean] True if tick is fresh, false otherwise
      def fresh?(segment, security_id, max_age: 30)
        tick = get(segment, security_id)
        return false unless tick&.dig(:timestamp)

        (Time.now - tick[:timestamp]) <= max_age
      end

      # Get statistics about the cache
      # @return [Hash] Cache statistics
      def stats
        {
          total_ticks: MAP.size,
          segments: MAP.values.map { |t| t[:segment] }.uniq,
          oldest_tick: MAP.values.map { |t| t[:timestamp] }.compact.min,
          newest_tick: MAP.values.map { |t| t[:timestamp] }.compact.max
        }
      end
    end
  end
end
