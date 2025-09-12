# frozen_string_literal: true

require "concurrent"
require_relative "candle_series"
require_relative "services/rate_limiter"

module DhanScalper
  class OHLCFetcher
    def initialize(config, logger: nil)
      @config = config
      @logger = logger || Logger.new($stdout)
      @running = false
      @fetch_thread = nil
      @candle_cache = Concurrent::Map.new
      @fetch_interval = config.dig("global", "ohlc_fetch_interval") || 180 # 3 minutes
      @last_fetch_times = Concurrent::Map.new
    end

    def start
      return if @running

      @running = true
      @logger.info "[OHLC] Starting OHLC fetcher (interval: #{@fetch_interval}s)"

      @fetch_thread = Thread.new do
        fetch_loop
      end
    end

    def stop
      return unless @running

      @running = false
      @fetch_thread&.join(2)
      @logger.info "[OHLC] OHLC fetcher stopped"
    end

    def running?
      @running
    end

    def get_candle_data(symbol, timeframe = "1m")
      cache_key = "#{symbol}_#{timeframe}"
      @candle_cache[cache_key]
    end

    def get_latest_candle(symbol, timeframe = "1m")
      candle_data = get_candle_data(symbol, timeframe)
      return nil unless candle_data&.candles&.any?

      candle_data.candles.last
    end

    def get_candle_series(symbol, timeframe = "1m")
      get_candle_data(symbol, timeframe)
    end

    def cache_stats
      {
        total_cached: @candle_cache.size,
        symbols: @candle_cache.keys.map { |k| k.split("_").first }.uniq,
        timeframes: @candle_cache.keys.map { |k| k.split("_").last }.uniq,
        last_fetch_times: begin
          @last_fetch_times.to_h
        rescue StandardError
          {}
        end,
      }
    end

    private

    def fetch_loop
      while @running
        begin
          fetch_all_symbols
          sleep(@fetch_interval)
        rescue StandardError => e
          @logger.error "[OHLC] Error in fetch loop: #{e.message}"
          @logger.error "[OHLC] Backtrace: #{e.backtrace.first(3).join("\n")}"
          sleep(30) # Wait before retrying
        end
      end
    end

    def fetch_all_symbols
      symbols = @config["SYMBOLS"]&.keys || []
      return if symbols.empty?

      @logger.info "[OHLC] Fetching data for #{symbols.size} symbols with staggering"

      # Implement round-robin staggering: NIFTY at 0s, BANKNIFTY at +10s, etc.
      symbols.each_with_index do |symbol, index|
        # Calculate stagger delay (10 seconds between symbols)
        stagger_delay = index * 10

        if stagger_delay > 0
          @logger.info "[OHLC] Staggering #{symbol} by #{stagger_delay}s"
          Thread.new do
            sleep(stagger_delay)
            fetch_symbol_data_with_rate_limit(symbol)
          end
        else
          # First symbol (index 0) fetches immediately
          fetch_symbol_data_with_rate_limit(symbol)
        end
      end
    end

    def fetch_symbol_data_with_rate_limit(symbol)
      fetch_symbol_data(symbol)

      # Rate limiting between symbols
      Services::RateLimiter.wait_if_needed("ohlc_fetch")
      sleep(1) # Additional delay between symbols
    end

    def fetch_symbol_data(symbol)
      symbol_config = @config["SYMBOLS"][symbol]
      return unless symbol_config

      begin
        # Fetch data for multiple timeframes
        timeframes = @config.dig("global", "ohlc_timeframes") || %w[1 5]

        timeframes.each do |interval|
          fetch_timeframe_data(symbol, symbol_config, interval)

          # Small delay between timeframes for same symbol
          sleep(0.5)
        end

        @last_fetch_times[symbol] = Time.now
        @logger.debug "[OHLC] Successfully fetched data for #{symbol}"
      rescue StandardError => e
        @logger.error "[OHLC] Error fetching data for #{symbol}: #{e.message}"
      end
    end

    def fetch_timeframe_data(symbol, symbol_config, interval)
      cache_key = "#{symbol}_#{interval}m"

      begin
        candle_series = CandleSeries.load_from_dhan_intraday(
          seg: symbol_config["seg_idx"],
          sid: symbol_config["idx_sid"],
          interval: interval,
          symbol: "INDEX",
        )

        if candle_series&.candles&.any?
          @candle_cache[cache_key] = candle_series
          @logger.debug "[OHLC] Cached #{candle_series.candles.size} candles for #{symbol} #{interval}m"
        else
          @logger.warn "[OHLC] No candle data received for #{symbol} #{interval}m"
        end
      rescue StandardError => e
        @logger.error "[OHLC] Error fetching #{symbol} #{interval}m data: #{e.message}"
      end
    end

    def should_fetch_symbol?(symbol)
      last_fetch = @last_fetch_times[symbol]
      return true unless last_fetch

      Time.now - last_fetch >= @fetch_interval
    end

    def get_cache_age(symbol, timeframe = "1m")
      cache_key = "#{symbol}_#{timeframe}"
      candle_data = @candle_cache[cache_key]
      return nil unless candle_data&.candles&.any?

      last_candle = candle_data.candles.last
      return nil unless last_candle&.timestamp

      Time.now - Time.at(last_candle.timestamp)
    end

    def is_data_fresh?(symbol, timeframe = "1m", max_age: 300)
      age = get_cache_age(symbol, timeframe)
      return false unless age

      age <= max_age
    end
  end
end
