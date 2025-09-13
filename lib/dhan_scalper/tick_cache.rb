# frozen_string_literal: true

require "concurrent"

module DhanScalper
  class TickCache
    MAP = Concurrent::Map.new

    class << self
      # Store a tick in the cache
      # @param tick [Hash] The tick data with keys like :segment, :security_id, :ltp, etc.
      def put(tick)
        puts "Putting tick: #{tick.inspect}" if ENV["DHAN_LOG_LEVEL"] == "DEBUG"
        return unless tick.is_a?(Hash) && tick[:segment] && tick[:security_id]

        key = "#{tick[:segment]}:#{tick[:security_id]}"
        # For :oi ticks, merge with existing data to avoid overwriting price fields
        if tick[:kind] == :oi && MAP[key]
          existing_data = MAP[key]
          # Remove nil values from the new tick to avoid overwriting existing data
          new_tick_clean = tick.compact
          MAP[key] = existing_data.merge(new_tick_clean).merge(timestamp: Time.now)
        else
          MAP[key] = tick.merge(timestamp: Time.now)
        end
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
      def ltp(segment, security_id, use_fallback: true)
        tick = get(segment, security_id)
        if tick.nil? && use_fallback
          # Try fallback API
          return ltp_fallback(segment, security_id)
        end

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
          oldest_tick: MAP.values.filter_map { |t| t[:timestamp] }.min,
          newest_tick: MAP.values.filter_map { |t| t[:timestamp] }.max,
        }
      end


      # Fallback method to get LTP from DhanHQ API when not cached
      # @param segment [String] Exchange segment
      # @param security_id [String] Security ID
      # @return [Float, nil] The LTP or nil if not found
      def ltp_fallback(segment, security_id)
        return nil unless defined?(DhanScalper::Services::LtpFallback)

        begin
          # Use a singleton instance to avoid creating multiple instances
          @ltp_fallback ||= DhanScalper::Services::LtpFallback.new
          tick_data = @ltp_fallback.get_ltp(segment, security_id)

          if tick_data
            # Store the fetched data in cache
            put(tick_data)
            return tick_data[:ltp]
          end

          nil
        rescue StandardError
          # Silently fail to avoid disrupting normal operation
          nil
        end
      end
    end
  end
end
