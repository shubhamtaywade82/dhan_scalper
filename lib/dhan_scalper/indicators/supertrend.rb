# frozen_string_literal: true

module DhanScalper
  module Indicators
    # Supertrend indicator with internal ATR fallback
    class Supertrend
      def initialize(series:, period: 10, multiplier: 3.0)
        @series     = series
        @period     = period.to_i
        @multiplier = multiplier.to_f
      end

      # Returns an Array<Float|nil> aligned with candle indices
      def call
        highs  = @series.highs
        lows   = @series.lows
        closes = @series.closes
        n = closes.size
        return [] if n.zero?

        # 1) ATR (Wilder)
        trs = Array.new(n)
        trs[0] = (highs[0].to_f - lows[0].to_f).abs
        (1...n).each do |i|
          h_l  = (highs[i].to_f - lows[i].to_f).abs
          h_pc = (highs[i].to_f - closes[i - 1].to_f).abs
          l_pc = (lows[i].to_f  - closes[i - 1].to_f).abs
          trs[i] = [h_l, h_pc, l_pc].max
        end

        atr = Array.new(n)
        if n >= @period
          sum = trs[0...@period].sum
          atr_val = sum / @period.to_f
          atr[@period - 1] = atr_val
          (@period...n).each do |i|
            atr_val = ((atr_val * (@period - 1)) + trs[i]) / @period.to_f
            atr[i] = atr_val
          end
        end

        # 2) Basic bands
        upperband = Array.new(n)
        lowerband = Array.new(n)
        (0...n).each do |i|
          next if atr[i].nil?
          mid = (highs[i].to_f + lows[i].to_f) / 2.0
          upperband[i] = mid + (@multiplier * atr[i])
          lowerband[i] = mid - (@multiplier * atr[i])
        end

        # 3) Final bands and supertrend
        st = Array.new(n)
        (0...n).each do |i|
          next if atr[i].nil?
          if i == @period
            next if upperband[i].nil? || lowerband[i].nil?
            st[i] = closes[i].to_f <= upperband[i] ? upperband[i] : lowerband[i]
            next
          end

          prev_st = st[i - 1]
          prev_up = upperband[i - 1]
          prev_dn = lowerband[i - 1]
          cur_up  = upperband[i]
          cur_dn  = lowerband[i]
          close   = closes[i].to_f

          # Skip if any required values are nil
          next if prev_st.nil? || prev_up.nil? || prev_dn.nil? || cur_up.nil? || cur_dn.nil?

          if prev_st == prev_up
            st[i] = close <= cur_up ? [cur_up, prev_st].min : cur_dn
          else
            st[i] = close >= cur_dn ? [cur_dn, prev_st].max : cur_up
          end
        end

        st
      end
    end
  end
end

