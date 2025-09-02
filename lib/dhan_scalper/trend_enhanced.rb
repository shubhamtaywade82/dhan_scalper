# frozen_string_literal: true

require_relative "candle_series"

module DhanScalper
  class TrendEnhanced
    def initialize(seg_idx:, sid_idx:, use_multi_timeframe: true, secondary_timeframe: 3)
      @seg_idx = seg_idx
      @sid_idx = sid_idx
      @use_multi_timeframe = use_multi_timeframe
      @secondary_timeframe = secondary_timeframe
    end

    def decide
      # Load 1-minute candle series
      c1_series = CandleSeries.load_from_dhan_intraday(
        seg: @seg_idx,
        sid: @sid_idx,
        interval: "1",
        symbol: "INDEX"
      )

      return :none if c1_series.nil? || c1_series.candles.size < 100

      # Load secondary timeframe if multi-timeframe is enabled
      if @use_multi_timeframe
        c_series = CandleSeries.load_from_dhan_intraday(
          seg: @seg_idx,
          sid: @sid_idx,
          interval: @secondary_timeframe.to_s,
          symbol: "INDEX"
        )
        return :none if c_series.nil? || c_series.candles.size < 100
      end

      # Try Holy Grail indicator first (more comprehensive)
      begin
        hg_1m = c1_series.holy_grail

        if @use_multi_timeframe
          hg_tf = c_series.holy_grail

          if hg_1m&.proceed? && hg_tf&.proceed?
            # Both timeframes agree on direction
            if hg_1m.bias == :bullish && hg_tf.bias == :bullish &&
               hg_1m.momentum == :up && hg_tf.momentum == :up
              puts "[TrendEnhanced] Holy Grail: Strong bullish signal (1m: bias=#{hg_1m.bias}, momentum=#{hg_1m.momentum}, adx=#{hg_1m.adx.round(1)})"
              puts "[TrendEnhanced] Holy Grail: Strong bullish signal (#{@secondary_timeframe}m: bias=#{hg_tf.bias}, momentum=#{hg_tf.momentum}, adx=#{hg_tf.adx.round(1)})"
              return :long_ce
            elsif hg_1m.bias == :bearish && hg_tf.bias == :bearish &&
                  hg_1m.momentum == :down && hg_tf.momentum == :down
              puts "[TrendEnhanced] Holy Grail: Strong bearish signal (1m: bias=#{hg_1m.bias}, momentum=#{hg_1m.momentum}, adx=#{hg_1m.adx.round(1)})"
              puts "[TrendEnhanced] Holy Grail: Strong bearish signal (#{@secondary_timeframe}m: bias=#{hg_tf.bias}, momentum=#{hg_tf.momentum}, adx=#{hg_tf.adx.round(1)})"
              return :long_pe
            else
              puts "[TrendEnhanced] Holy Grail: Mixed signals (1m: bias=#{hg_1m.bias}, momentum=#{hg_1m.momentum}) (#{@secondary_timeframe}m: bias=#{hg_tf.bias}, momentum=#{hg_tf.momentum})"
            end
          else
            puts "[TrendEnhanced] Holy Grail: Not proceeding (1m: proceed=#{hg_1m&.proceed?}, #{@secondary_timeframe}m: proceed=#{hg_tf&.proceed?})"
          end
        else
          # Single timeframe analysis
          if hg_1m&.proceed?
            if hg_1m.bias == :bullish && hg_1m.momentum == :up
              puts "[TrendEnhanced] Holy Grail: Bullish signal (1m: bias=#{hg_1m.bias}, momentum=#{hg_1m.momentum}, adx=#{hg_1m.adx.round(1)})"
              return :long_ce
            elsif hg_1m.bias == :bearish && hg_1m.momentum == :down
              puts "[TrendEnhanced] Holy Grail: Bearish signal (1m: bias=#{hg_1m.bias}, momentum=#{hg_1m.momentum}, adx=#{hg_1m.adx.round(1)})"
              return :long_pe
            end
          else
            puts "[TrendEnhanced] Holy Grail: Not proceeding (1m: proceed=#{hg_1m&.proceed?})"
          end
        end

        # Fallback to combined signal
        signal_1m = c1_series.combined_signal

        if @use_multi_timeframe
          signal_tf = c_series.combined_signal

          if signal_1m == :strong_buy && signal_tf == :strong_buy
            puts "[TrendEnhanced] Combined: Strong buy signal"
            return :long_ce
          elsif signal_1m == :strong_sell && signal_tf == :strong_sell
            puts "[TrendEnhanced] Combined: Strong sell signal"
            return :long_pe
          elsif signal_1m == :weak_buy && signal_tf == :weak_buy
            puts "[TrendEnhanced] Combined: Weak buy signal"
            return :long_ce
          elsif signal_1m == :weak_sell && signal_tf == :weak_sell
            puts "[TrendEnhanced] Combined: Weak sell signal"
            return :long_pe
          end
        else
          # Single timeframe combined signal
          if signal_1m == :strong_buy || signal_1m == :weak_buy
            puts "[TrendEnhanced] Combined: Buy signal (1m: #{signal_1m})"
            return :long_ce
          elsif signal_1m == :strong_sell || signal_1m == :weak_sell
            puts "[TrendEnhanced] Combined: Sell signal (1m: #{signal_1m})"
            return :long_pe
          end
        end

      rescue StandardError => e
        puts "[TrendEnhanced] Holy Grail failed, falling back to simple indicators: #{e.message}"
      end

      # Fallback to Supertrend
      begin
        st_signal_1m = c1_series.supertrend_signal

        if @use_multi_timeframe
          st_signal_tf = c_series.supertrend_signal

          if st_signal_1m == :bullish && st_signal_tf == :bullish
            puts "[TrendEnhanced] Supertrend: Bullish signal"
            return :long_ce
          elsif st_signal_1m == :bearish && st_signal_tf == :bearish
            puts "[TrendEnhanced] Supertrend: Bearish signal"
            return :long_pe
          end
        else
          # Single timeframe Supertrend
          if st_signal_1m == :bullish
            puts "[TrendEnhanced] Supertrend: Bullish signal (1m)"
            return :long_ce
          elsif st_signal_1m == :bearish
            puts "[TrendEnhanced] Supertrend: Bearish signal (1m)"
            return :long_pe
          end
        end
      rescue StandardError => e
        puts "[TrendEnhanced] Supertrend failed: #{e.message}"
      end

      # Final fallback to original simple indicators
      begin
        e1f = c1_series.ema(20).last
        e1s = c1_series.ema(50).last
        r1 = c1_series.rsi(14).last

        if @use_multi_timeframe
          etf = c_series.ema(20).last
          ets = c_series.ema(50).last
          rt = c_series.rsi(14).last

          up   = e1f > e1s && r1 > 55 && etf > ets && rt > 52
          down = e1f < e1s && r1 < 45 && etf < ets && rt < 48

          if up
            puts "[TrendEnhanced] Simple: Bullish signal (EMA: 1m=#{e1f > e1s}, #{@secondary_timeframe}m=#{etf > ets}, RSI: 1m=#{r1.round(1)}, #{@secondary_timeframe}m=#{rt.round(1)})"
            return :long_ce
          elsif down
            puts "[TrendEnhanced] Simple: Bearish signal (EMA: 1m=#{e1f < e1s}, #{@secondary_timeframe}m=#{etf < ets}, RSI: 1m=#{r1.round(1)}, #{@secondary_timeframe}m=#{rt.round(1)})"
            return :long_pe
          end
        else
          # Single timeframe simple indicators
          up   = e1f > e1s && r1 > 55
          down = e1f < e1s && r1 < 45

          if up
            puts "[TrendEnhanced] Simple: Bullish signal (EMA: 1m=#{e1f > e1s}, RSI: 1m=#{r1.round(1)})"
            return :long_ce
          elsif down
            puts "[TrendEnhanced] Simple: Bearish signal (EMA: 1m=#{e1f < e1s}, RSI: 1m=#{r1.round(1)})"
            return :long_pe
          end
        end
      rescue StandardError => e
        puts "[TrendEnhanced] Simple indicators failed: #{e.message}"
      end

      puts "[TrendEnhanced] No clear signal"
      :none
    end
  end
end
