# frozen_string_literal: true

require "concurrent"
begin
  require "redis"
  require "connection_pool"
rescue LoadError
  # optional; fallback to memory
end

module DhanScalper
  class TickCache
    MAP = Concurrent::Map.new
    REDIS_POOL = if ENV["TICK_CACHE_BACKEND"] == "redis" && defined?(Redis) && defined?(ConnectionPool)
                   ConnectionPool.new(size: ENV.fetch("REDIS_POOL", "5").to_i, timeout: 1) do
                     Redis.new(url: ENV.fetch("REDIS_URL", "redis://127.0.0.1:6379/0"))
                   end
                 end
    NAMESPACE = ENV.fetch("REDIS_NAMESPACE", nil)

    class << self
      # Store a tick in the cache
      # @param tick [Hash] The tick data with keys like :segment, :security_id, :ltp, etc.
      def put(tick)
        # puts "Putting tick: #{tick.inspect}"
        return unless tick.is_a?(Hash) && tick[:segment] && tick[:security_id]

        if REDIS_POOL
          key = namespaced(tick_key(tick[:segment], tick[:security_id]))
          REDIS_POOL.with do |r|
            r.hset(key, tick.transform_keys(&:to_s))
            r.expire(key, 60)
          end
        else
          key = "#{tick[:segment]}:#{tick[:security_id]}"
          MAP[key] = tick.merge(timestamp: Time.now)
        end
      end

      # Get a tick from the cache
      # @param segment [String] Exchange segment (e.g., "NSE_FNO", "IDX_I")
      # @param security_id [String] Security ID
      # @return [Hash, nil] The tick data or nil if not found
      def get(segment, security_id)
        if REDIS_POOL
          key = namespaced(tick_key(segment, security_id))
          h = REDIS_POOL.with { |r| r.hgetall(key) }
          return nil if h.nil? || h.empty?

          # coerce numeric fields if present
          h = h.transform_keys(&:to_sym)
          h[:ltp] = begin
            (h[:ltp].include?(".") ? h[:ltp].to_f : h[:ltp].to_i)
          rescue StandardError
            h[:ltp]
          end
          h
        else
          key = "#{segment}:#{security_id}"
          MAP[key]
        end
      end

      # Get the LTP (Last Traded Price) for a specific instrument
      # @param segment [String] Exchange segment
      # @param security_id [String] Security ID
      # @return [Float, nil] The LTP or nil if not found
      def ltp(segment, security_id, use_fallback: true)
        if REDIS_POOL
          key = namespaced(tick_key(segment, security_id))
          v = REDIS_POOL.with { |r| r.hget(key, "ltp") }
          if v.nil? && use_fallback
            # Try fallback API
            return ltp_fallback(segment, security_id)
          end
          return nil if v.nil?
          return v if v.is_a?(String) && v.match?(/[^0-9.]/)

          begin
            v.include?(".") ? v.to_f : v.to_i
          rescue StandardError
            v
          end
        else
          tick = get(segment, security_id)
          if tick.nil? && use_fallback
            # Try fallback API
            return ltp_fallback(segment, security_id)
          end

          tick&.dig(:ltp)
        end
      end

      # Get all cached ticks
      # @return [Hash] All cached ticks
      def all
        if REDIS_POOL
          # lightweight: only return counts when using redis
          { total_ticks: stats[:total_ticks] }
        else
          result = {}
          MAP.each { |key, value| result[key] = value }
          result
        end
      end

      # Clear all cached data
      def clear
        if REDIS_POOL
          # best-effort: do nothing to avoid wild-card deletes; tests use memory backend
          true
        else
          MAP.clear
        end
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
        if REDIS_POOL
          # use TTL as freshness proxy
          key = namespaced(tick_key(segment, security_id))
          ttl = REDIS_POOL.with { |r| r.ttl(key) }
          ttl && ttl > 0 && ttl <= 60
        else
          tick = get(segment, security_id)
          return false unless tick&.dig(:timestamp)

          (Time.now - tick[:timestamp]) <= max_age
        end
      end

      # Get statistics about the cache
      # @return [Hash] Cache statistics
      def stats
        if REDIS_POOL
          # Approximate: count keys by scan
          total = 0
          cursor = "0"
          begin
            loop do
              res = REDIS_POOL.with { |r| r.scan(cursor, match: namespaced("ticks:*"), count: 100) }
              cursor, keys = res
              total += keys.size
              break if cursor == "0"
            end
          rescue StandardError
            total = 0
          end
          { total_ticks: total, segments: [] }
        else
          {
            total_ticks: MAP.size,
            segments: MAP.values.map { |t| t[:segment] }.uniq,
            oldest_tick: MAP.values.map { |t| t[:timestamp] }.compact.min,
            newest_tick: MAP.values.map { |t| t[:timestamp] }.compact.max,
          }
        end
      end

      def tick_key(seg, sid) = "ticks:#{seg}:#{sid}"

      def namespaced(key)
        return key unless NAMESPACE && !NAMESPACE.empty?

        "#{NAMESPACE}:#{key}"
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
