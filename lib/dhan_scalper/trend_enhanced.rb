# frozen_string_literal: true

require_relative "candle_series"

module DhanScalper
  class TrendEnhanced
    def initialize(seg_idx:, sid_idx:)
      @seg_idx = seg_idx
      @sid_idx = sid_idx
    end

    def decide
      # Load candle series for 1-minute and 5-minute intervals
      c1_series = CandleSeries.load_from_dhan_intraday(
        seg: @seg_idx,
        sid: @sid_idx,
        interval: "1",
        symbol: "INDEX"
      )
      c5_series = CandleSeries.load_from_dhan_intraday(
        seg: @seg_idx,
        sid: @sid_idx,
        interval: "5",
        symbol: "INDEX"
      )

      return :none if c1_series.nil? || c5_series.nil?
      return :none if c1_series.candles.size < 100 || c5_series.candles.size < 100

      # Try Holy Grail indicator first (more comprehensive)
      begin
        hg_1m = c1_series.holy_grail
        hg_5m = c5_series.holy_grail

        if hg_1m&.proceed? && hg_5m&.proceed?
          # Both timeframes agree on direction
          if hg_1m.bias == :bullish && hg_5m.bias == :bullish &&
             hg_1m.momentum == :up && hg_5m.momentum == :up
            puts "[TrendEnhanced] Holy Grail: Strong bullish signal (1m: bias=#{hg_1m.bias}, momentum=#{hg_1m.momentum}, adx=#{hg_1m.adx.round(1)})"
            puts "[TrendEnhanced] Holy Grail: Strong bullish signal (5m: bias=#{hg_5m.bias}, momentum=#{hg_5m.momentum}, adx=#{hg_5m.adx.round(1)})"
            return :long_ce
          elsif hg_1m.bias == :bearish && hg_5m.bias == :bearish &&
                hg_1m.momentum == :down && hg_5m.momentum == :down
            puts "[TrendEnhanced] Holy Grail: Strong bearish signal (1m: bias=#{hg_1m.bias}, momentum=#{hg_1m.momentum}, adx=#{hg_1m.adx.round(1)})"
            puts "[TrendEnhanced] Holy Grail: Strong bearish signal (5m: bias=#{hg_5m.bias}, momentum=#{hg_5m.momentum}, adx=#{hg_5m.adx.round(1)})"
            return :long_pe
          else
            puts "[TrendEnhanced] Holy Grail: Mixed signals (1m: bias=#{hg_1m.bias}, momentum=#{hg_1m.momentum}) (5m: bias=#{hg_5m.bias}, momentum=#{hg_5m.momentum})"
          end
        else
          puts "[TrendEnhanced] Holy Grail: Not proceeding (1m: proceed=#{hg_1m&.proceed?}, 5m: proceed=#{hg_5m&.proceed?})"
        end

        # Fallback to combined signal
        signal_1m = c1_series.combined_signal
        signal_5m = c5_series.combined_signal

        if signal_1m == :strong_buy && signal_5m == :strong_buy
          puts "[TrendEnhanced] Combined: Strong buy signal"
          return :long_ce
        elsif signal_1m == :strong_sell && signal_5m == :strong_sell
          puts "[TrendEnhanced] Combined: Strong sell signal"
          return :long_pe
        elsif signal_1m == :weak_buy && signal_5m == :weak_buy
          puts "[TrendEnhanced] Combined: Weak buy signal"
          return :long_ce
        elsif signal_1m == :weak_sell && signal_5m == :weak_sell
          puts "[TrendEnhanced] Combined: Weak sell signal"
          return :long_pe
        end

      rescue StandardError => e
        puts "[TrendEnhanced] Holy Grail failed, falling back to simple indicators: #{e.message}"
      end

      # Fallback to Supertrend
      begin
        st_signal_1m = c1_series.supertrend_signal
        st_signal_5m = c5_series.supertrend_signal

        if st_signal_1m == :bullish && st_signal_5m == :bullish
          puts "[TrendEnhanced] Supertrend: Bullish signal"
          return :long_ce
        elsif st_signal_1m == :bearish && st_signal_5m == :bearish
          puts "[TrendEnhanced] Supertrend: Bearish signal"
          return :long_pe
        end
      rescue StandardError => e
        puts "[TrendEnhanced] Supertrend failed: #{e.message}"
      end

      # Final fallback to original simple indicators
      begin
        e1f = c1_series.ema(20).last
        e1s = c1_series.ema(50).last
        r1 = c1_series.rsi(14).last
        e5f = c5_series.ema(20).last
        e5s = c5_series.ema(50).last
        r5 = c5_series.rsi(14).last

        up   = e1f > e1s && r1 > 55 && e5f > e5s && r5 > 52
        down = e1f < e1s && r1 < 45 && e5f < e5s && r5 < 48

        if up
          puts "[TrendEnhanced] Simple: Bullish signal (EMA: 1m=#{e1f > e1s}, 5m=#{e5f > e5s}, RSI: 1m=#{r1.round(1)}, 5m=#{r5.round(1)})"
          return :long_ce
        elsif down
          puts "[TrendEnhanced] Simple: Bearish signal (EMA: 1m=#{e1f < e1s}, 5m=#{e5f < e5s}, RSI: 1m=#{r1.round(1)}, 5m=#{r5.round(1)})"
          return :long_pe
        end
      rescue StandardError => e
        puts "[TrendEnhanced] Simple indicators failed: #{e.message}"
      end

      puts "[TrendEnhanced] No clear signal"
      :none
    end
  end
end
