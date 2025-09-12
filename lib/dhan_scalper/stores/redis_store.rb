# frozen_string_literal: true

require "redis"
require "json"
require "digest"

module DhanScalper
  module Stores
    # Redis store for canonical key structure and operations
    class RedisStore
      attr_reader :redis, :namespace, :logger

      def initialize(namespace: "dhan_scalper:v1", redis_url: nil, logger: nil)
        @namespace = namespace
        @redis_url = redis_url || ENV.fetch("REDIS_URL", "redis://127.0.0.1:6379/0")
        @logger = logger || Logger.new($stdout)
        @redis = nil
        @process_id = Process.pid
        @hot_cache = {} # In-process cache for hot path data
      end

      # Connect to Redis and verify ping
      def connect
        @logger.info "[REDIS_STORE] Connecting to Redis at #{@redis_url}..."

        @redis = Redis.new(url: @redis_url)

        # Verify connection with ping
        begin
          response = @redis.ping
          raise "Redis ping failed" unless response == "PONG"

          @logger.info "[REDIS_STORE] Redis connected successfully"
        rescue StandardError => e
          @logger.error "[REDIS_STORE] Redis connection failed: #{e.message}"
          raise
        end
      end

      # Disconnect from Redis
      def disconnect
        @redis&.close
        @redis = nil
        @logger.info "[REDIS_STORE] Disconnected from Redis"
      end

      # Store configuration
      def store_config(config)
        key = "#{@namespace}:cfg"
        @redis.set(key, config.to_json)
        @redis.expire(key, 86_400) # 24 hours TTL
        @logger.info "[REDIS_STORE] Configuration cached at #{key}"
      end

      # Get configuration
      def get_config
        key = "#{@namespace}:cfg"
        data = @redis.get(key)
        return nil unless data

        JSON.parse(data, symbolize_names: false)
      end

      # Store CSV raw data checksum
      def store_csv_checksum(checksum, timestamp = Time.now.to_i)
        key = "#{@namespace}:csv:raw"
        @redis.hset(key, "checksum", checksum)
        @redis.hset(key, "timestamp", timestamp)
        @redis.expire(key, 86_400) # 24 hours TTL
      end

      # Get CSV checksum
      def get_csv_checksum
        key = "#{@namespace}:csv:raw"
        data = @redis.hgetall(key)
        return nil if data.empty?

        {
          checksum: data["checksum"],
          timestamp: data["timestamp"].to_i,
        }
      end

      # Store CSV raw checksum (alias for store_csv_checksum)
      def store_csv_raw_checksum(checksum_data)
        if checksum_data.is_a?(Hash)
          checksum = checksum_data[:checksum] || checksum_data["checksum"]
          timestamp = checksum_data[:timestamp] || checksum_data["timestamp"] || Time.now.to_i
        else
          checksum = checksum_data
          timestamp = Time.now.to_i
        end
        store_csv_checksum(checksum, timestamp)
      end

      # Get CSV raw checksum (alias for get_csv_checksum)
      def get_csv_raw_checksum
        get_csv_checksum
      end

      # Store universe SIDs
      def store_universe_sids(sids)
        key = "#{@namespace}:universe:sids"
        @redis.del(key)
        @redis.sadd(key, sids) if sids.any?
        @redis.expire(key, 86_400) # 24 hours TTL
      end

      # Get universe SIDs
      def get_universe_sids
        key = "#{@namespace}:universe:sids"
        @redis.smembers(key)
      end

      # Check if security ID is in universe
      def universe_contains?(security_id)
        key = "#{@namespace}:universe:sids"
        @redis.sismember(key, security_id)
      end

      # Store symbol metadata
      def store_symbol_metadata(symbol, metadata)
        key = "#{@namespace}:sym:#{symbol}:meta"
        @redis.hset(key, metadata.transform_keys(&:to_s).flatten)
        @redis.expire(key, 86_400) # 24 hours TTL
      end

      # Get symbol metadata
      def get_symbol_metadata(symbol)
        key = "#{@namespace}:sym:#{symbol}:meta"
        data = @redis.hgetall(key)
        return nil if data.empty?

        # Convert values back to appropriate types
        result = {}
        data.each do |k, v|
          key_sym = k.to_sym
          result[key_sym] = case key_sym
                            when :lot_size, :strike_step
                              v.to_i
                            else
                              v
                            end
        end
        result
      end

      # Store tick data (with hot cache)
      def store_tick(segment, security_id, tick_data)
        key = "#{@namespace}:ticks:#{segment}:#{security_id}"

        # Store in Redis
        @redis.hset(key, tick_data.transform_keys(&:to_s))
        @redis.expire(key, 300) # 5 minutes TTL

        # Update hot cache
        cache_key = "#{segment}:#{security_id}"
        @hot_cache[cache_key] = {
          data: tick_data,
          cached_at: Time.now,
        }

        # Update LTP hot cache
        ltp_cache_key = "#{segment}:#{security_id}:ltp"
        @hot_cache[ltp_cache_key] = {
          data: tick_data[:ltp],
          cached_at: Time.now,
        }
      end

      # Get tick data (with hot cache)
      def get_tick(segment, security_id)
        cache_key = "#{segment}:#{security_id}"

        # Check hot cache first
        if @hot_cache[cache_key] && (Time.now - @hot_cache[cache_key][:cached_at]) < 1
          return @hot_cache[cache_key][:data]
        end

        # Get from Redis
        key = "#{@namespace}:ticks:#{segment}:#{security_id}"
        data = @redis.hgetall(key)
        return nil if data.empty?

        # Convert string values to appropriate types
        tick_data = {
          ltp: data["ltp"]&.to_f,
          ts: data["ts"]&.to_i,
          atp: data["atp"]&.to_f,
          vol: data["vol"]&.to_i,
          segment: data["segment"],
          security_id: data["security_id"],
        }

        # Update hot cache
        @hot_cache[cache_key] = {
          data: tick_data,
          cached_at: Time.now,
        }

        tick_data
      end

      # Get LTP (with hot cache)
      def get_ltp(segment, security_id)
        cache_key = "#{segment}:#{security_id}:ltp"

        # Check hot cache first
        if @hot_cache[cache_key] && (Time.now - @hot_cache[cache_key][:cached_at]) < 1
          return @hot_cache[cache_key][:data]
        end

        # Get from Redis
        key = "#{@namespace}:ticks:#{segment}:#{security_id}"
        ltp = @redis.hget(key, "ltp")
        return nil unless ltp

        ltp_value = ltp.to_f

        # Update hot cache
        @hot_cache[cache_key] = {
          data: ltp_value,
          cached_at: Time.now,
        }

        ltp_value
      end

      # Store minute bars
      def store_minute_bar(segment, security_id, minute, candle_data)
        key = "#{@namespace}:bars:#{segment}:#{security_id}:#{minute}"
        @redis.lpush(key, candle_data.to_json)
        @redis.ltrim(key, 0, 99) # Keep last 100 bars
        @redis.expire(key, 86_400) # 24 hours TTL
      end

      # Get minute bars
      def get_minute_bars(segment, security_id, minute, count = 10)
        key = "#{@namespace}:bars:#{segment}:#{security_id}:#{minute}"
        bars = @redis.lrange(key, 0, count - 1)
        bars.map { |bar| JSON.parse(bar, symbolize_names: true) }
      end

      # Store order
      def store_order(order_id, order_data)
        key = "#{@namespace}:order:#{order_id}"
        @redis.hset(key, order_data.transform_keys(&:to_s))
        @redis.expire(key, 86_400) # 24 hours TTL
      end

      # Get order
      def get_order(order_id)
        key = "#{@namespace}:order:#{order_id}"
        data = @redis.hgetall(key)
        return nil if data.empty?

        data.transform_keys(&:to_sym)
      end

      # Add order to session
      def add_order_to_session(mode, session_id, order_id)
        key = "#{@namespace}:orders:#{mode}:#{session_id}"
        @redis.lpush(key, order_id)
        @redis.expire(key, 86_400) # 24 hours TTL
      end

      # Get session orders
      def get_session_orders(mode, session_id)
        key = "#{@namespace}:orders:#{mode}:#{session_id}"
        @redis.lrange(key, 0, -1)
      end

      # Store position
      def store_position(position_id, position_data)
        key = "#{@namespace}:pos:#{position_id}"
        @redis.hset(key, position_data.transform_keys(&:to_s))
        @redis.expire(key, 86_400) # 24 hours TTL
      end

      # Get position
      def get_position(position_id)
        key = "#{@namespace}:pos:#{position_id}"
        data = @redis.hgetall(key)
        return nil if data.empty?

        data.transform_keys(&:to_sym)
      end

      # Add position to open positions
      def add_open_position(position_id)
        key = "#{@namespace}:pos:open"
        @redis.sadd(key, position_id)
        @redis.expire(key, 86_400) # 24 hours TTL
      end

      # Remove position from open positions
      def remove_open_position(position_id)
        key = "#{@namespace}:pos:open"
        @redis.srem(key, position_id)
      end

      # Get open positions
      def get_open_positions
        key = "#{@namespace}:pos:open"
        @redis.smembers(key)
      end

      # Store session PnL
      def store_session_pnl(_session_id, pnl_data)
        key = "#{@namespace}:pnl:session"
        @redis.hset(key, "realized", pnl_data[:realized] || pnl_data["realized"])
        @redis.hset(key, "unrealized", pnl_data[:unrealized] || pnl_data["unrealized"])
        @redis.hset(key, "fees", pnl_data[:fees] || pnl_data["fees"])
        @redis.hset(key, "total", pnl_data[:total] || pnl_data["total"])
        @redis.hset(key, "timestamp", pnl_data[:timestamp] || pnl_data["timestamp"] || Time.now.to_i)
        @redis.expire(key, 86_400) # 24 hours TTL
      end

      # Get session PnL
      def get_session_pnl(_session_id = nil)
        key = "#{@namespace}:pnl:session"
        data = @redis.hgetall(key)
        return nil if data.empty?

        {
          realized: data["realized"].to_f,
          unrealized: data["unrealized"].to_f,
          fees: data["fees"].to_f,
          total: data["total"].to_f,
          timestamp: data["timestamp"].to_i,
        }
      end

      # Store report
      def store_report(session_id, report_data)
        key = "#{@namespace}:reports:#{session_id}"
        @redis.hset(key, "csv_path", report_data[:csv_path] || report_data["csv_path"])
        @redis.hset(key, "json_path", report_data[:json_path] || report_data["json_path"])
        @redis.hset(key, "total_trades", report_data[:total_trades] || report_data["total_trades"])
        @redis.hset(key, "total_pnl", report_data[:total_pnl] || report_data["total_pnl"])
        @redis.hset(key, "generated_at", report_data[:generated_at] || report_data["generated_at"] || Time.now.to_i)
        @redis.expire(key, 86_400) # 24 hours TTL
      end

      # Get report
      def get_report(session_id)
        key = "#{@namespace}:reports:#{session_id}"
        data = @redis.hgetall(key)
        return nil if data.empty?

        {
          csv_path: data["csv_path"],
          json_path: data["json_path"],
          total_trades: data["total_trades"].to_i,
          total_pnl: data["total_pnl"].to_f,
          generated_at: data["generated_at"].to_i,
        }
      end

      # Setup heartbeat
      def setup_heartbeat
        heartbeat_key = "#{@namespace}:hb"
        @redis.hset(heartbeat_key, @process_id.to_s, Time.now.to_i)
        @redis.expire(heartbeat_key, 300) # 5 minutes TTL
      end

      # Store heartbeat (alias for setup_heartbeat)
      def store_heartbeat
        setup_heartbeat
      end

      # Update heartbeat
      def update_heartbeat
        heartbeat_key = "#{@namespace}:hb"
        @redis.hset(heartbeat_key, @process_id.to_s, Time.now.to_i)
        @redis.expire(heartbeat_key, 300) # 5 minutes TTL
      end

      # Get heartbeat data
      def get_heartbeat
        heartbeat_key = "#{@namespace}:hb"
        data = @redis.hgetall(heartbeat_key)
        return nil if data.empty?

        # Convert string keys to integers for timestamps
        data.transform_values(&:to_i)
      end

      # Acquire advisory lock
      def acquire_lock(lock_name, owner, ttl = 60)
        key = "#{@namespace}:locks:#{lock_name}"
        lock_value = "#{owner}:#{Time.now.to_i + ttl}"

        # Try to set lock if it doesn't exist
        return true if @redis.set(key, lock_value, nx: true, ex: ttl)

        # Check if existing lock is expired
        existing = @redis.get(key)
        if existing
          _, expiry_part = existing.split(":")
          if expiry_part && Time.now.to_i > expiry_part.to_i && @redis.set(key, lock_value, xx: true, ex: ttl)
            # Lock is expired, try to replace it
            return true
          end
        end

        false
      end

      # Release advisory lock
      def release_lock(lock_name, owner)
        key = "#{@namespace}:locks:#{lock_name}"
        existing = @redis.get(key)
        return false unless existing

        _owner_part, _expiry_part = existing.split(":")
        if _owner_part == owner
          @redis.del(key)
          return true
        end

        false
      end

      # Check throttle
      def check_throttle(throttle_name, interval_seconds = 60)
        key = "#{@namespace}:throttle:#{throttle_name}"
        last_time = @redis.get(key)

        if last_time
          last_timestamp = last_time.to_i
          if Time.now.to_i - last_timestamp < interval_seconds
            return false # Throttled
          end
        end

        @redis.set(key, Time.now.to_i, ex: interval_seconds)
        true # Not throttled
      end

      # Clear hot cache
      def clear_hot_cache
        @hot_cache.clear
      end

      # Get hot cache stats
      def hot_cache_stats
        {
          size: @hot_cache.size,
          keys: @hot_cache.keys,
        }
      end

      # Cache instruments for symbols
      # @param symbols [Array<String>] Array of symbol names
      # @param instruments [Hash] Hash with symbol as key and array of instruments as value
      def cache_instruments(symbols, instruments)
        return if symbols.empty? || instruments.empty?

        symbols.each do |symbol|
          symbol_instruments = instruments[symbol] || []
          key = "#{@namespace}:instruments:#{symbol.downcase}"

          # Store as JSON array
          @redis.setex(key, 3_600, JSON.generate(symbol_instruments)) # 1 hour TTL
        end

        # Store cache metadata
        cache_key = "#{@namespace}:instruments:cache"
        @redis.hset(cache_key, {
                      symbols: symbols.join(","),
                      timestamp: Time.now.to_i,
                      count: instruments.values.sum(&:size),
                    })
      end

      # Get cached instruments for symbols
      # @param symbols [Array<String>] Array of symbol names
      # @return [Hash, nil] Cached instruments or nil if not found
      def get_cached_instruments(symbols)
        return nil if symbols.empty?

        # Check cache metadata
        cache_key = "#{@namespace}:instruments:cache"
        cache_data = @redis.hgetall(cache_key)
        return nil if cache_data.empty?

        cached_symbols = cache_data["symbols"]&.split(",") || []
        return nil unless (symbols - cached_symbols).empty?

        # Check if cache is still valid (less than 1 hour old)
        cache_timestamp = cache_data["timestamp"]&.to_i
        return nil unless cache_timestamp && (Time.now.to_i - cache_timestamp) < 3_600

        # Load cached instruments
        result = {}
        symbols.each do |symbol|
          key = "#{@namespace}:instruments:#{symbol.downcase}"
          cached_data = @redis.get(key)
          return nil unless cached_data

          result[symbol] = JSON.parse(cached_data, symbolize_names: true)

          # Cache incomplete
        end

        result
      end

      # Clear instruments cache
      def clear_instruments_cache
        # Get all instrument cache keys
        pattern = "#{@namespace}:instruments:*"
        keys = @redis.keys(pattern)
        @redis.del(*keys) if keys.any?
      end

      # Idempotency methods
      def store_idempotency_key(idempotency_key, order_id)
        key = "#{@namespace}:idemp:#{idempotency_key}"
        @redis.setex(key, 86_400, order_id) # 24 hours TTL
        @logger.debug "[REDIS_STORE] Stored idempotency key: #{idempotency_key} -> #{order_id}"
      end

      def get_idempotency_key(idempotency_key)
        key = "#{@namespace}:idemp:#{idempotency_key}"
        order_id = @redis.get(key)
        @logger.debug "[REDIS_STORE] Retrieved idempotency key: #{idempotency_key} -> #{order_id}" if order_id
        order_id
      end

      def has_idempotency_key?(idempotency_key)
        key = "#{@namespace}:idemp:#{idempotency_key}"
        @redis.exists?(key)
      end

      def delete_idempotency_key(idempotency_key)
        key = "#{@namespace}:idemp:#{idempotency_key}"
        @redis.del(key)
        @logger.debug "[REDIS_STORE] Deleted idempotency key: #{idempotency_key}"
      end
    end
  end
end
