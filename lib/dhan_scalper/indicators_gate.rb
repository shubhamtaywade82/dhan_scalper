# frozen_string_literal: true

module DhanScalper
  module IndicatorsGate
    module_function

    # return full EMA series (Array<Float>) to align with CandleSeries usage
    def ema_series(values, period)
      if defined?(TechnicalAnalysis) && TechnicalAnalysis.respond_to?(:ema)
        return TechnicalAnalysis.ema(data: values, period: period)
      elsif defined?(RubyTechnicalAnalysis)
        return RubyTechnicalAnalysis::Indicator::Ema.new(period: period).calculate(values)
      end

      # fallback
      k = 2.0 / (period + 1)
      e = nil
      values.map { |v| e = e.nil? ? v.to_f : ((v.to_f * k) + (e * (1 - k))) }
    end

    def rsi_series(values, period = 14)
      if defined?(TechnicalAnalysis) && TechnicalAnalysis.respond_to?(:rsi)
        return TechnicalAnalysis.rsi(data: values, period: period)
      elsif defined?(RubyTechnicalAnalysis)
        return RubyTechnicalAnalysis::Indicator::Rsi.new(period: period).calculate(values)
      end
      # fallback simple RSI
      return Array.new(values.size) { 50.0 } if values.size < period + 1

      gains = []
      losses = []
      (1...values.size).each do |i|
        d = values[i].to_f - values[i - 1].to_f
        gains << [d, 0].max
        losses << [-d, 0].max
      end
      ag = gains.first(period).sum / period.to_f
      al = losses.first(period).sum / period.to_f
      out = []
      # pad initial
      period.times { out << 50.0 }
      (period...gains.size).each do |i|
        ag = ((ag * (period - 1)) + gains[i]) / period
        al = ((al * (period - 1)) + losses[i]) / period
        rs = al.zero? ? 100.0 : ag / al
        out << (100 - (100 / (1 + rs)))
      end
      out.unshift(*Array.new(values.size - out.size, 50.0))
      out
    end

    # Donchian (from intrinio gem)
    def donchian(values_hlc, period: 20)
      if defined?(TechnicalAnalysis)
        begin
          return TechnicalAnalysis.dc(values_hlc, period: period)
        rescue StandardError
          []
        end
      end
      []
    end

    def atr(values_hlc, period: 14)
      if defined?(TechnicalAnalysis)
        begin
          res = TechnicalAnalysis.atr(values_hlc, period: period)
          return res
        rescue StandardError
          # fall through to pure-Ruby implementation
        end
      end

      # Pure-Ruby ATR (Wilder) fallback
      n = values_hlc.size
      return [] if n.zero?

      highs = values_hlc.map { |x| (x[:high] || x['high']).to_f }
      lows  = values_hlc.map { |x| (x[:low]  || x['low']).to_f }
      closes = values_hlc.map { |x| (x[:close] || x['close']).to_f }

      trs = Array.new(n, 0.0)
      trs[0] = (highs[0] - lows[0]).abs
      (1...n).each do |i|
        h_l = (highs[i] - lows[i]).abs
        h_pc = (highs[i] - closes[i - 1]).abs
        l_pc = (lows[i]  - closes[i - 1]).abs
        trs[i] = [h_l, h_pc, l_pc].max
      end

      atr = Array.new(n)
      if n >= period
        sum = trs[0...period].sum
        atr_val = sum / period.to_f
        atr[period - 1] = atr_val
        (period...n).each do |i|
          atr_val = ((atr_val * (period - 1)) + trs[i]) / period.to_f
          atr[i] = atr_val
        end
      end
      atr
    end
  end
end

# Provide a top-level alias for specs and external callers expecting `IndicatorsGate`
IndicatorsGate = DhanScalper::IndicatorsGate unless defined?(IndicatorsGate)
