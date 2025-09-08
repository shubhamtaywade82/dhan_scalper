# frozen_string_literal: true

require_relative "candle_series"

module DhanScalper
  class TrendEnhanced
    VALID_INTERVALS = [1, 5, 15, 25, 60].freeze

    def initialize(seg_idx:, sid_idx:, use_multi_timeframe: true, secondary_timeframe: 5)
      @seg_idx = seg_idx
      @sid_idx = sid_idx
      @use_multi_timeframe = use_multi_timeframe
      @secondary_timeframe = validate_interval(secondary_timeframe)
    end

    def decide
      # Load 1-minute candle series
      begin
        c1_series = CandleSeries.load_from_dhan_intraday(
          seg: @seg_idx,
          sid: @sid_idx,
          interval: "1",
          symbol: "INDEX"
        )

        if c1_series.nil? || c1_series.candles.nil? || c1_series.candles.size < 100
          puts "[TrendEnhanced] Insufficient 1m data: #{c1_series&.candles&.size || 0} candles"
          return :none
        end
      rescue StandardError => e
        puts "[TrendEnhanced] Failed to load 1m data: #{e.message}"
        return :none
      end

      # Load secondary timeframe if multi-timeframe is enabled
      if @use_multi_timeframe
        begin
          c_series = CandleSeries.load_from_dhan_intraday(
            seg: @seg_idx,
            sid: @sid_idx,
            interval: @secondary_timeframe.to_s,
            symbol: "INDEX"
          )
          if c_series.nil? || c_series.candles.nil? || c_series.candles.size < 100
            puts "[TrendEnhanced] Insufficient #{@secondary_timeframe}m data: #{c_series&.candles&.size || 0} candles"
            return :none
          end
        rescue StandardError => e
          puts "[TrendEnhanced] Failed to load #{@secondary_timeframe}m data: #{e.message}"
          return :none
        end
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
            # Enhanced logging for multi-timeframe
            reasons = []

            if hg_1m
              reasons << "1m_proceed=#{hg_1m.proceed?}"
              unless hg_1m.proceed?
                hg_1m_reasons = []
                hg_1m_reasons << "bias=#{hg_1m.bias}" if hg_1m.bias
                hg_1m_reasons << "momentum=#{hg_1m.momentum}" if hg_1m.momentum
                hg_1m_reasons << "adx=#{hg_1m.adx.round(1)}" if hg_1m.adx
                if hg_1m.bias == :neutral
                  hg_1m_reasons << "bias_neutral"
                elsif hg_1m.bias == :bullish && hg_1m.momentum != :up
                  hg_1m_reasons << "bullish_but_momentum_not_up"
                elsif hg_1m.bias == :bearish && hg_1m.momentum != :down
                  hg_1m_reasons << "bearish_but_momentum_not_down"
                end
                adx_threshold = hg_1m.adx_threshold || 15.0
                if hg_1m.adx && hg_1m.adx < adx_threshold
                  hg_1m_reasons << "adx_weak(#{hg_1m.adx.round(1)}<#{adx_threshold})"
                end
                reasons << "1m_reasons=[#{hg_1m_reasons.join(", ")}]"
              end
            else
              reasons << "1m=nil"
            end

            if hg_tf
              reasons << "#{@secondary_timeframe}m_proceed=#{hg_tf.proceed?}"
              unless hg_tf.proceed?
                hg_tf_reasons = []
                hg_tf_reasons << "bias=#{hg_tf.bias}" if hg_tf.bias
                hg_tf_reasons << "momentum=#{hg_tf.momentum}" if hg_tf.momentum
                hg_tf_reasons << "adx=#{hg_tf.adx.round(1)}" if hg_tf.adx
                if hg_tf.bias == :neutral
                  hg_tf_reasons << "bias_neutral"
                elsif hg_tf.bias == :bullish && hg_tf.momentum != :up
                  hg_tf_reasons << "bullish_but_momentum_not_up"
                elsif hg_tf.bias == :bearish && hg_tf.momentum != :down
                  hg_tf_reasons << "bearish_but_momentum_not_down"
                end
                adx_threshold = hg_tf.adx_threshold || 15.0
                if hg_tf.adx && hg_tf.adx < adx_threshold
                  hg_tf_reasons << "adx_weak(#{hg_tf.adx.round(1)}<#{adx_threshold})"
                end
                reasons << "#{@secondary_timeframe}m_reasons=[#{hg_tf_reasons.join(", ")}]"
              end
            else
              reasons << "#{@secondary_timeframe}m=nil"
            end

            puts "[TrendEnhanced] Holy Grail: Not proceeding (#{reasons.join(", ")})"
          end
        elsif hg_1m&.proceed?
          # Single timeframe analysis
          if hg_1m.bias == :bullish && hg_1m.momentum == :up
            puts "[TrendEnhanced] Holy Grail: Bullish signal (1m: bias=#{hg_1m.bias}, momentum=#{hg_1m.momentum}, adx=#{hg_1m.adx.round(1)})"
            return :long_ce
          elsif hg_1m.bias == :bearish && hg_1m.momentum == :down
            puts "[TrendEnhanced] Holy Grail: Bearish signal (1m: bias=#{hg_1m.bias}, momentum=#{hg_1m.momentum}, adx=#{hg_1m.adx.round(1)})"
            return :long_pe
          end
        elsif hg_1m
          # Enhanced logging for single timeframe
          reasons = []
          reasons << "bias=#{hg_1m.bias}" if hg_1m.bias
          reasons << "momentum=#{hg_1m.momentum}" if hg_1m.momentum
          reasons << "adx=#{hg_1m.adx.round(1)}" if hg_1m.adx
          reasons << "sma50=#{hg_1m.sma50.round(2)}" if hg_1m.sma50
          reasons << "ema200=#{hg_1m.ema200.round(2)}" if hg_1m.ema200
          reasons << "rsi=#{hg_1m.rsi14.round(1)}" if hg_1m.rsi14

          # Check specific conditions
          if hg_1m.bias == :neutral
            reasons << "bias_neutral"
          elsif hg_1m.bias == :bullish && hg_1m.momentum != :up
            reasons << "bullish_but_momentum_not_up"
          elsif hg_1m.bias == :bearish && hg_1m.momentum != :down
            reasons << "bearish_but_momentum_not_down"
          end

          adx_threshold = hg_1m.adx_threshold || 15.0
          reasons << "adx_weak(#{hg_1m.adx.round(1)}<#{adx_threshold})" if hg_1m.adx && hg_1m.adx < adx_threshold

          puts "[TrendEnhanced] Holy Grail: Not proceeding (1m: proceed=#{hg_1m.proceed?}, #{reasons.join(", ")})"
        else
          puts "[TrendEnhanced] Holy Grail: Not proceeding (1m: hg_1m=nil)"
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
        elsif %i[strong_buy weak_buy].include?(signal_1m)
          # Single timeframe combined signal
          puts "[TrendEnhanced] Combined: Buy signal (1m: #{signal_1m})"
          return :long_ce
        elsif %i[strong_sell weak_sell].include?(signal_1m)
          puts "[TrendEnhanced] Combined: Sell signal (1m: #{signal_1m})"
          return :long_pe
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
        elsif st_signal_1m == :bullish
          # Single timeframe Supertrend
          puts "[TrendEnhanced] Supertrend: Bullish signal (1m)"
          return :long_ce
        elsif st_signal_1m == :bearish
          puts "[TrendEnhanced] Supertrend: Bearish signal (1m)"
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

    private

    def validate_interval(interval)
      unless VALID_INTERVALS.include?(interval)
        puts "[WARNING] Invalid interval #{interval}, falling back to 5 minutes. Valid intervals: #{VALID_INTERVALS.join(", ")}"
        return 5
      end
      interval
    end
  end
end
