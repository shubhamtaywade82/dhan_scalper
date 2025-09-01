# frozen_string_literal: true

require_relative "candle_series"

module DhanScalper
  class TrendEnhanced
    def initialize(seg_idx:, sid_idx:)
      @seg_idx = seg_idx
      @sid_idx = sid_idx
    end

    def decide
      # Load candle series for 1-minute and 3-minute intervals
      c1_series = CandleSeries.load_from_dhan_intraday(
        seg: @seg_idx,
        sid: @sid_idx,
        interval: "1",
        symbol: "INDEX"
      )
      c3_series = CandleSeries.load_from_dhan_intraday(
        seg: @seg_idx,
        sid: @sid_idx,
        interval: "3",
        symbol: "INDEX"
      )

      return :none if c1_series.nil? || c3_series.nil?
      return :none if c1_series.candles.size < 100 || c3_series.candles.size < 100

      # Try Holy Grail indicator first (more comprehensive)
      begin
        hg_1m = c1_series.holy_grail
        hg_3m = c3_series.holy_grail

        pp hg_1m
        pp hg_3m
        if hg_1m&.proceed? && hg_3m&.proceed?
          # Both timeframes agree on direction
          if hg_1m.bias == :bullish && hg_3m.bias == :bullish &&
             hg_1m.momentum == :up && hg_3m.momentum == :up
            puts "[TrendEnhanced] Holy Grail: Strong bullish signal (1m: bias=#{hg_1m.bias}, momentum=#{hg_1m.momentum}, adx=#{hg_1m.adx.round(1)})"
            puts "[TrendEnhanced] Holy Grail: Strong bullish signal (3m: bias=#{hg_3m.bias}, momentum=#{hg_3m.momentum}, adx=#{hg_3m.adx.round(1)})"
            return :long_ce
          elsif hg_1m.bias == :bearish && hg_3m.bias == :bearish &&
                hg_1m.momentum == :down && hg_3m.momentum == :down
            puts "[TrendEnhanced] Holy Grail: Strong bearish signal (1m: bias=#{hg_1m.bias}, momentum=#{hg_1m.momentum}, adx=#{hg_1m.adx.round(1)})"
            puts "[TrendEnhanced] Holy Grail: Strong bearish signal (3m: bias=#{hg_3m.bias}, momentum=#{hg_3m.momentum}, adx=#{hg_3m.adx.round(1)})"
            return :long_pe
          else
            puts "[TrendEnhanced] Holy Grail: Mixed signals (1m: bias=#{hg_1m.bias}, momentum=#{hg_1m.momentum}) (3m: bias=#{hg_3m.bias}, momentum=#{hg_3m.momentum})"
          end
        else
          puts "[TrendEnhanced] Holy Grail: Not proceeding (1m: proceed=#{hg_1m&.proceed?}, 3m: proceed=#{hg_3m&.proceed?})"
        end

        # Fallback to combined signal
        signal_1m = c1_series.combined_signal
        signal_3m = c3_series.combined_signal

        if signal_1m == :strong_buy && signal_3m == :strong_buy
          puts "[TrendEnhanced] Combined: Strong buy signal"
          return :long_ce
        elsif signal_1m == :strong_sell && signal_3m == :strong_sell
          puts "[TrendEnhanced] Combined: Strong sell signal"
          return :long_pe
        elsif signal_1m == :weak_buy && signal_3m == :weak_buy
          puts "[TrendEnhanced] Combined: Weak buy signal"
          return :long_ce
        elsif signal_1m == :weak_sell && signal_3m == :weak_sell
          puts "[TrendEnhanced] Combined: Weak sell signal"
          return :long_pe
        end

      rescue StandardError => e
        puts "[TrendEnhanced] Holy Grail failed, falling back to simple indicators: #{e.message}"
      end

      # Fallback to Supertrend
      begin
        st_signal_1m = c1_series.supertrend_signal
        st_signal_3m = c3_series.supertrend_signal

        if st_signal_1m == :bullish && st_signal_3m == :bullish
          puts "[TrendEnhanced] Supertrend: Bullish signal"
          return :long_ce
        elsif st_signal_1m == :bearish && st_signal_3m == :bearish
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
        e3f = c3_series.ema(20).last
        e3s = c3_series.ema(50).last
        r3 = c3_series.rsi(14).last

        up   = e1f > e1s && r1 > 55 && e3f > e3s && r3 > 52
        down = e1f < e1s && r1 < 45 && e3f < e3s && r3 < 48

        if up
          puts "[TrendEnhanced] Simple: Bullish signal (EMA: 1m=#{e1f > e1s}, 3m=#{e3f > e3s}, RSI: 1m=#{r1.round(1)}, 3m=#{r3.round(1)})"
          return :long_ce
        elsif down
          puts "[TrendEnhanced] Simple: Bearish signal (EMA: 1m=#{e1f < e1s}, 3m=#{e3f < e3s}, RSI: 1m=#{r1.round(1)}, 3m=#{r3.round(1)})"
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
