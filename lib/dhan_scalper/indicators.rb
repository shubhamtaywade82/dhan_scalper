# frozen_string_literal: true

module DhanScalper
  module Indicators
    module_function

    def ema_last(values, period)
      if defined?(TechnicalAnalysis) && TechnicalAnalysis.respond_to?(:ema)
        TechnicalAnalysis.ema(data: values, period: period).last.to_f
      elsif defined?(RubyTechnicalAnalysis)
        RubyTechnicalAnalysis::Indicator::Ema.new(period: period).calculate(values).last.to_f
      else
        k = 2.0 / (period + 1)
        ema = nil
        values.each { |v| ema = ema.nil? ? v.to_f : (v.to_f * k + ema * (1 - k)) }
        ema.to_f
      end
    rescue StandardError
      values.last.to_f
    end

    def rsi_last(values, period = 14)
      if defined?(TechnicalAnalysis) && TechnicalAnalysis.respond_to?(:rsi)
        TechnicalAnalysis.rsi(data: values, period: period).last.to_f
      elsif defined?(RubyTechnicalAnalysis)
        RubyTechnicalAnalysis::Indicator::Rsi.new(period: period).calculate(values).last.to_f
      else
        # simple fallback
        return 50.0 if values.size < period + 1

        gains = []
        losses = []
        (1...values.size).each do |i|
          d = values[i].to_f - values[i - 1].to_f
          gains << [d, 0].max
          losses << [-d, 0].max
        end
        ag = gains.first(period).sum / period
        al = losses.first(period).sum / period
        (period...gains.size).each do |i|
          ag = (ag * (period - 1) + gains[i]) / period
          al = (al * (period - 1) + losses[i]) / period
        end
        rs = al.zero? ? 100.0 : ag / al
        100 - (100 / (1 + rs))
      end
    rescue StandardError
      50.0
    end
  end
end
