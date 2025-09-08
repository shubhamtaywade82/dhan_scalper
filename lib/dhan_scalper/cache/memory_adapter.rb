# frozen_string_literal: true

require "concurrent"

module DhanScalper
  module Cache
    # Memory cache adapter as fallback when Redis is not available
    class MemoryAdapter
      attr_reader :cache, :ttl_cache, :logger

      def initialize(logger: nil)
        @cache = Concurrent::Map.new
        @ttl_cache = Concurrent::Map.new
        @logger = logger || Logger.new($stdout)
      end

      def get(key)
        return nil unless @cache.key?(key)

        # Check TTL
        if @ttl_cache.key?(key)
          ttl_data = @ttl_cache[key]
          if Time.now > ttl_data[:expires_at]
            @cache.delete(key)
            @ttl_cache.delete(key)
            return nil
          end
        end

        @cache[key]
      end

      def set(key, value, ttl: nil)
        @cache[key] = value

        if ttl
          @ttl_cache[key] = {
            expires_at: Time.now + ttl,
            ttl: ttl
          }
        end

        true
      end

      def del(key)
        @cache.delete(key)
        @ttl_cache.delete(key)
        true
      end

      def exists?(key)
        return false unless @cache.key?(key)

        # Check TTL
        if @ttl_cache.key?(key)
          ttl_data = @ttl_cache[key]
          if Time.now > ttl_data[:expires_at]
            @cache.delete(key)
            @ttl_cache.delete(key)
            return false
          end
        end

        true
      end

      def atomic_update_peak(security_id, current_price, entry_price)
        key = "peak:#{security_id}"
        existing_peak = get(key)&.to_f || entry_price

        if current_price > existing_peak
          set(key, current_price.to_s, ttl: 3600)
          current_price
        else
          existing_peak
        end
      end

      def atomic_update_trigger(security_id, new_trigger, current_trigger)
        key = "trigger:#{security_id}"
        existing_trigger = get(key)&.to_f || current_trigger

        if new_trigger > existing_trigger
          set(key, new_trigger.to_s, ttl: 3600)
          new_trigger
        else
          existing_trigger
        end
      end

      def get_peak_price(security_id)
        get("peak:#{security_id}")&.to_f
      end

      def get_trigger_price(security_id)
        get("trigger:#{security_id}")&.to_f
      end

      def set_heartbeat
        set("feed:heartbeat", Time.now.iso8601, ttl: 120)
      end

      def get_heartbeat
        get("feed:heartbeat")
      end

      def set_trend_status(security_id, status)
        set("trend:#{security_id}", status, ttl: 300) # 5 minutes TTL
      end

      def get_trend_status(security_id)
        get("trend:#{security_id}")
      end

      def set_dedupe_key(key, ttl: 10)
        dedupe_key = "dedupe:#{key}"
        return false if exists?(dedupe_key)

        set(dedupe_key, "1", ttl: ttl)
        true
      end

      def clear_dedupe_key(key)
        del("dedupe:#{key}")
      end

      def get_all_positions
        positions = {}
        @cache.each do |key, value|
          next unless key.start_with?("position:")

          security_id = key.split(":").last
          positions[security_id] = value
        end

        positions
      end

      def set_position(security_id, position_data)
        key = "position:#{security_id}"
        set(key, position_data, ttl: 3600) # 1 hour TTL
        true
      end

      def del_position(security_id)
        del("position:#{security_id}")
      end

      def ping
        true
      end

      def disconnect
        @cache.clear
        @ttl_cache.clear
      end

      def cleanup_expired
        now = Time.now
        expired_keys = []

        @ttl_cache.each do |key, ttl_data|
          expired_keys << key if now > ttl_data[:expires_at]
        end

        expired_keys.each do |key|
          @cache.delete(key)
          @ttl_cache.delete(key)
        end

        expired_keys.size
      end
    end
  end
end
