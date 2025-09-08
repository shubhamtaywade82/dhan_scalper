# frozen_string_literal: true

require "redis"

module DhanScalper
  module Cache
    # Redis adapter for advanced market data caching with atomic operations
    class RedisAdapter
      attr_reader :redis, :logger

      def initialize(url: nil, logger: nil)
        @redis = Redis.new(url: url || ENV["REDIS_URL"] || "redis://localhost:6379/0")
        @logger = logger || Logger.new($stdout)
        @lua_scripts = {}
        load_lua_scripts
      end

      def get(key)
        @redis.get(key)
      rescue Redis::BaseError => e
        @logger.error "[REDIS] Get error for key #{key}: #{e.message}"
        nil
      end

      def set(key, value, ttl: nil)
        if ttl
          @redis.setex(key, ttl, value)
        else
          @redis.set(key, value)
        end
        true
      rescue Redis::BaseError => e
        @logger.error "[REDIS] Set error for key #{key}: #{e.message}"
        false
      end

      def del(key)
        @redis.del(key)
      rescue Redis::BaseError => e
        @logger.error "[REDIS] Delete error for key #{key}: #{e.message}"
        false
      end

      def exists?(key)
        @redis.exists?(key)
      rescue Redis::BaseError => e
        @logger.error "[REDIS] Exists error for key #{key}: #{e.message}"
        false
      end

      def atomic_update_peak(security_id, current_price, entry_price)
        script = @lua_scripts[:update_peak]
        @redis.eval(script, keys: ["peak:#{security_id}"], argv: [current_price.to_s, entry_price.to_s])
      rescue Redis::BaseError => e
        @logger.error "[REDIS] Atomic peak update error: #{e.message}"
        nil
      end

      def atomic_update_trigger(security_id, new_trigger, current_trigger)
        script = @lua_scripts[:update_trigger]
        @redis.eval(script, keys: ["trigger:#{security_id}"], argv: [new_trigger.to_s, current_trigger.to_s])
      rescue Redis::BaseError => e
        @logger.error "[REDIS] Atomic trigger update error: #{e.message}"
        nil
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
        keys = @redis.keys("position:*")
        return {} if keys.empty?

        positions = {}
        keys.each do |key|
          position_data = @redis.hgetall(key)
          next if position_data.empty?

          security_id = key.split(":").last
          positions[security_id] = position_data.transform_values { |v| v.include?(".") ? v.to_f : v }
        end

        positions
      rescue Redis::BaseError => e
        @logger.error "[REDIS] Get all positions error: #{e.message}"
        {}
      end

      def set_position(security_id, position_data)
        key = "position:#{security_id}"
        @redis.hset(key, position_data.transform_values(&:to_s))
        @redis.expire(key, 3600) # 1 hour TTL
        true
      rescue Redis::BaseError => e
        @logger.error "[REDIS] Set position error: #{e.message}"
        false
      end

      def del_position(security_id)
        del("position:#{security_id}")
      end

      def ping
        @redis.ping == "PONG"
      rescue Redis::BaseError
        false
      end

      def disconnect
        @redis.disconnect
      end

      private

      def load_lua_scripts
        @lua_scripts = {
          update_peak: <<~LUA
              local key = KEYS[1]
              local current_price = tonumber(ARGV[1])
              local entry_price = tonumber(ARGV[2])

              local existing_peak = redis.call('GET', key)
              local peak_price = existing_peak and tonumber(existing_peak) or entry_price

              if current_price > peak_price then
                redis.call('SET', key, current_price)
                redis.call('EXPIRE', key, 3600)
                return current_price
              else
                return peak_price
              end
            LUA,

            update_trigger: <<~LUA
              local key = KEYS[1]
              local new_trigger = tonumber(ARGV[1])
              local current_trigger = tonumber(ARGV[2])

              local existing_trigger = redis.call('GET', key)
              local trigger_price = existing_trigger and tonumber(existing_trigger) or current_trigger

              if new_trigger > trigger_price then
                redis.call('SET', key, new_trigger)
                redis.call('EXPIRE', key, 3600)
                return new_trigger
              else
                return trigger_price
              end
          LUA
        }
      end
    end
  end
end
