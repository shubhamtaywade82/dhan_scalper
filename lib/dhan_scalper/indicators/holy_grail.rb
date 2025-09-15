# frozen_string_literal: true

require_relative '../support/application_service'

module DhanScalper
  module Indicators
    class HolyGrail < DhanScalper::ApplicationService
      # External libraries not required - using fallback implementations
      RTA = nil
      TA  = nil

      EMA_FAST = 34
      EMA_SLOW = 100
      RSI_LEN  = 14
      ADX_LEN  = 14
      ATR_LEN  = 20
      MACD_F   = 12
      MACD_S   = 26
      MACD_SIG = 9

      Result = Struct.new(
        :bias, :adx, :momentum, :proceed?,
        :sma50, :ema200, :rsi14, :atr14, :macd, :trend,
        :options_signal, :signal_strength, :adx_threshold,
        keyword_init: true
      ) do
        def to_h = members.zip(values).to_h
      end

      def initialize(candles:)
        # expect hash-of-arrays like CandleSeries#to_hash
        @candles = candles
        closes = @candles.fetch('close') { [] }
        raise ArgumentError, "need ≥ #{EMA_SLOW} candles" if closes.size < EMA_SLOW
      end

      def call
        sma50  = sma(EMA_FAST)
        ema200 = ema(EMA_SLOW)
        rsi14  = rsi(RSI_LEN)
        macd_h = macd_hash
        adx14  = adx(ADX_LEN)
        atr14  = atr(ATR_LEN)

        bias = if sma50 > ema200 then :bullish
               elsif sma50 < ema200 then :bearish
               else
                 :neutral
               end

        momentum = if macd_h[:macd].to_f > macd_h[:signal].to_f && rsi14 > 50
                     :up
                   elsif macd_h[:macd].to_f < macd_h[:signal].to_f && rsi14 < 50
                     :down
                   else
                     :flat
                   end

        # Dynamic ADX threshold based on timeframe
        adx_threshold = get_adx_threshold

        proceed = case bias
                  when :bullish then adx14.to_f >= adx_threshold && momentum == :up
                  when :bearish then adx14.to_f >= adx_threshold && momentum == :down
                  else false
                  end

        trend = if ema200 < closes_last && sma50 > ema200 then :up
                elsif ema200 > closes_last && sma50 < ema200 then :down
                else
                  :side
                end

        # Generate options buying signal
        options_signal, signal_strength = generate_options_signal(bias, momentum, adx14, rsi14, macd_h)

        Result.new(
          bias: bias, adx: adx14, momentum: momentum, proceed?: proceed,
          sma50: sma50, ema200: ema200, rsi14: rsi14, atr14: atr14, macd: macd_h, trend: trend,
          options_signal: options_signal, signal_strength: signal_strength,
          adx_threshold: adx_threshold
        )
      end

      private

      def closes = @candles.fetch('close') { [] }.map(&:to_f)
      def highs  = @candles.fetch('high')  { [] }.map(&:to_f)
      def lows   = @candles.fetch('low')   { [] }.map(&:to_f)
      def stamps = @candles['timestamp'] || []
      def closes_last = closes.last.to_f

      def ohlc_rows
        @ohlc_rows ||= highs.each_index.map do |i|
          { date_time: DhanScalper::TimeZone.at(stamps[i] || 0), high: highs[i], low: lows[i], close: closes[i] }
        end
      end

      # basic SMA over last len closes
      def sma(len)
        arr = closes.last(len)
        return 0.0 if arr.empty?

        arr.sum / len.to_f
      end

      def ema(len)
        return RTA::MovingAverages.new(series: closes, period: len).ema if RTA

        # fallback simple EMA
        k = 2.0 / (len + 1)
        e = nil
        closes.each { |v| e = e.nil? ? v.to_f : ((v.to_f * k) + (e * (1 - k))) }
        e.to_f
      end

      def rsi(len)
        return RTA::RelativeStrengthIndex.new(series: closes, period: len).call if RTA
        # fallback: calculate RSI manually
        return 50.0 if closes.size < len + 1

        gains = []
        losses = []

        (1...closes.size).each do |i|
          change = closes[i] - closes[i - 1]
          if change.positive?
            gains << change
            losses << 0
          else
            gains << 0
            losses << -change
          end
        end

        return 50.0 if gains.size < len

        avg_gain = gains.last(len).sum / len.to_f
        avg_loss = losses.last(len).sum / len.to_f

        return 50.0 if avg_loss.zero?

        rs = avg_gain / avg_loss
        100 - (100 / (1 + rs))
      end

      def macd_hash
        if RTA
          m, s, h = RTA::Macd.new(series: closes, fast_period: MACD_F, slow_period: MACD_S,
                                  signal_period: MACD_SIG).call
          return { macd: m, signal: s, hist: h }
        end
        # fallback: calculate MACD manually
        return { macd: 0.0, signal: 0.0, hist: 0.0 } if closes.size < MACD_S

        # Calculate EMAs
        ema_fast = ema(MACD_F)
        ema_slow = ema(MACD_S)

        macd_line = ema_fast - ema_slow

        # For signal line, we need to calculate EMA of MACD line
        # This is a simplified version - in practice you'd need to track MACD values over time
        signal_line = macd_line * 0.9 # Simplified signal line
        histogram = macd_line - signal_line

        { macd: macd_line, signal: signal_line, hist: histogram }
      end

      def atr(len)
        if TA
          begin
            res = TA::Atr.calculate(ohlc_rows.last(len * 2), period: len)
            return res.first.atr
          rescue StandardError
          end
        end
        # fallback: calculate ATR manually
        return 0.0 if highs.size < len || lows.size < len || closes.size < len

        true_ranges = []
        (1...highs.size).each do |i|
          tr1 = highs[i] - lows[i]
          tr2 = (highs[i] - closes[i - 1]).abs
          tr3 = (lows[i] - closes[i - 1]).abs
          true_ranges << [tr1, tr2, tr3].max
        end

        return 0.0 if true_ranges.size < len

        # Calculate ATR using Wilder's smoothing
        atr_values = []
        atr_values << (true_ranges[0...len].sum / len.to_f)

        (len...true_ranges.size).each do |i|
          prev_atr = atr_values.last
          atr_values << (((prev_atr * (len - 1)) + true_ranges[i]) / len.to_f)
        end

        atr_values.last || 0.0
      end

      def adx(len)
        if TA
          begin
            res = TA::Adx.calculate(ohlc_rows.last(len * 2), period: len)
            return res.first.adx
          rescue StandardError
          end
        end
        # fallback: calculate ADX manually
        return 20.0 if highs.size < len * 2 || lows.size < len * 2 || closes.size < len * 2

        # Calculate +DM and -DM
        plus_dm = []
        minus_dm = []

        (1...highs.size).each do |i|
          high_diff = highs[i] - highs[i - 1]
          low_diff = lows[i - 1] - lows[i]

          if high_diff > low_diff && high_diff.positive?
            plus_dm << high_diff
            minus_dm << 0
          elsif low_diff > high_diff && low_diff.positive?
            plus_dm << 0
            minus_dm << low_diff
          else
            plus_dm << 0
            minus_dm << 0
          end
        end

        return 20.0 if plus_dm.size < len

        # Calculate smoothed +DM and -DM
        plus_dm_smooth = plus_dm.last(len).sum / len.to_f
        minus_dm_smooth = minus_dm.last(len).sum / len.to_f

        # Calculate True Range (simplified)
        tr_sum = 0.0
        (1...highs.size).each do |i|
          tr1 = highs[i] - lows[i]
          tr2 = (highs[i] - closes[i - 1]).abs
          tr3 = (lows[i] - closes[i - 1]).abs
          tr_sum += [tr1, tr2, tr3].max
        end
        tr_avg = tr_sum / (highs.size - 1)

        return 20.0 if tr_avg.zero?

        # Calculate +DI and -DI
        plus_di = 100 * (plus_dm_smooth / tr_avg)
        minus_di = 100 * (minus_dm_smooth / tr_avg)

        # Calculate DX
        di_sum = plus_di + minus_di
        return 20.0 if di_sum.zero?

        100 * ((plus_di - minus_di).abs / di_sum)

        # ADX is typically smoothed DX, but for simplicity return DX
      end

      # Generate options buying signal based on Holy Grail analysis
      def generate_options_signal(bias, momentum, adx, rsi, macd)
        return [:none, 0.0] unless bias && momentum && adx && rsi && macd

        # Base signal strength calculation
        signal_strength = 0.0

        # ADX strength (0-1)
        adx_strength = [adx.to_f / 50.0, 1.0].min
        signal_strength += adx_strength * 0.3

        # RSI momentum (0-1)
        rsi_strength = case bias
                       when :bullish
                         [(rsi.to_f - 50.0) / 50.0, 1.0].min
                       when :bearish
                         [(50.0 - rsi.to_f) / 50.0, 1.0].min
                       else
                         0.0
                       end
        signal_strength += rsi_strength * 0.2

        # MACD momentum (0-1)
        macd_strength = case bias
                        when :bullish
                          macd[:macd].to_f > macd[:signal].to_f ? 0.3 : 0.0
                        when :bearish
                          macd[:macd].to_f < macd[:signal].to_f ? 0.3 : 0.0
                        else
                          0.0
                        end
        signal_strength += macd_strength

        # Momentum alignment (0-1)
        momentum_strength = case bias
                            when :bullish
                              momentum == :up ? 0.2 : 0.0
                            when :bearish
                              momentum == :down ? 0.2 : 0.0
                            else
                              0.0
                            end
        signal_strength += momentum_strength

        # Determine options signal
        options_signal = case bias
                         when :bullish
                           if signal_strength >= 0.6
                             :buy_ce
                           elsif signal_strength >= 0.4
                             :buy_ce_weak
                           else
                             :none
                           end
                         when :bearish
                           if signal_strength >= 0.6
                             :buy_pe
                           elsif signal_strength >= 0.4
                             :buy_pe_weak
                           else
                             :none
                           end
                         else
                           :none
                         end

        [options_signal, signal_strength]
      end

      # Determine ADX threshold based on timeframe
      def get_adx_threshold
        # Try to determine timeframe from candle timestamps
        if stamps.size >= 2
          time_diff = stamps.last - stamps[-2]
          # Convert to minutes
          minutes = time_diff / 60.0

          case minutes
          when 0.5..1.5    # 1-minute timeframe
            10.0
          when 2.5..5.5    # 3-5 minute timeframes
            15.0
          else
            # Default for higher timeframes
            20.0
          end
        else
          # Default threshold if we can't determine timeframe
          15.0
        end
      end
    end
  end
end
