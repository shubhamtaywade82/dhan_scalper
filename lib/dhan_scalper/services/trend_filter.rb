# frozen_string_literal: true

require_relative "../tick_cache"

module DhanScalper
  module Services
    # TrendFilter generates directional signals and maintains a simple
    # streak window cache to ensure trend is ON for X minutes before entries.
    # It uses Supertrend + (optional) RSI/EMA confirmation from CandleSeries
    # when available; otherwise falls back to price vs. supertrend.
    class TrendFilter
      def initialize(logger:, cache:, config:, series_loader: nil, streak_window_minutes: 3)
        @logger = logger
        @cache = cache
        @config = config
        @series_loader = series_loader # callable: (seg:, sid:, interval:) -> CandleSeries
        @streak_window_seconds = Integer(streak_window_minutes) * 60
      end

      # Returns :long, :short, or :none
      def get_signal(symbol, _spot_price)
        cfg = yield_config(symbol)
        return :none unless cfg

        seg_idx = cfg["seg_idx"]
        idx_sid = cfg["idx_sid"]

        # Prefer CandleSeries (more robust); otherwise use tick-only heuristic
        signal = if @series_loader
                   decide_with_series(seg_idx, idx_sid)
                 else
                   decide_with_ticks(seg_idx, idx_sid)
                 end

        update_streak(symbol, signal)
        signal
      rescue StandardError => e
        @logger.error("[TREND] Error generating signal for #{symbol}: #{e.message}")
        :none
      end

      # When trend turns ON, record the start time; return Time or nil
      def get_streak_start(symbol)
        ts = @cache.get("trend_streak_start:#{symbol}")
        ts ? Time.parse(ts) : nil
      rescue StandardError
        nil
      end

      private

      def yield_config(symbol)
        # Expecting caller to pass a block resolving config for symbol
        # Example: trend_filter.get_signal(symbol, spot) { |s| config["SYMBOLS"][s] }
        # This indirection keeps service DRY/decoupled from config layout.
        @config.dig("SYMBOLS", symbol)
      end

      def decide_with_series(seg_idx, idx_sid)
        # Load 1m and 5m series; prefer Supertrend agreement
        c1 = @series_loader.call(seg: seg_idx, sid: idx_sid, interval: "1")
        c5 = @series_loader.call(seg: seg_idx, sid: idx_sid, interval: "5")
        return :none if c1.nil? || c5.nil?
        return :none if c1.candles.size < 50 || c5.candles.size < 50

        begin
          st1 = DhanScalper::Indicators::Supertrend.new(series: c1).call&.compact&.last
          st5 = DhanScalper::Indicators::Supertrend.new(series: c5).call&.compact&.last
          lc1 = c1.closes.last.to_f
          lc5 = c5.closes.last.to_f
          if st1 && st5
            up = lc1 > st1 && lc5 > st5
            down = lc1 < st1 && lc5 < st5
            return :long if up
            return :short if down
          end
        rescue StandardError
          # fall through to EMA/RSI
        end

        e1f = c1.ema(20).last
        e1s = c1.ema(50).last
        r1 = c1.rsi(14).last
        e5f = c5.ema(20).last
        e5s = c5.ema(50).last
        r5 = c5.rsi(14).last
        return :long if e1f > e1s && r1 > 55 && e5f > e5s && r5 > 52
        return :short if e1f < e1s && r1 < 45 && e5f < e5s && r5 < 48

        :none
      end

      def decide_with_ticks(seg_idx, idx_sid)
        # Minimal heuristic: trend unknown without series; return :none
        tick = DhanScalper::TickCache.get(seg_idx, idx_sid)
        tick ? :none : :none
      end

      def update_streak(symbol, signal)
        key_on = "trend_streak_on:#{symbol}"
        key_ts = "trend_streak_start:#{symbol}"

        if %i[long short].include?(signal)
          # If streak not already on, set start.
          @cache.set(key_on, "1", ttl: @streak_window_seconds)
          if @cache.exists?(key_on)
          # Refresh TTL while trend remains ON
          else
            @cache.set(key_ts, Time.now.iso8601, ttl: @streak_window_seconds)
          end
        else
          @cache.del(key_on)
          @cache.del(key_ts)
        end
      end
    end
  end
end
