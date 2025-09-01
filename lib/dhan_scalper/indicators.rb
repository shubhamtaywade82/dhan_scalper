module DhanScalper::Indicators
  module_function
  def ema_last(values, period)
    if defined?(TechnicalAnalysis) && TechnicalAnalysis.respond_to?(:ema)
      return TechnicalAnalysis.ema(data: values, period: period).last.to_f
    elsif defined?(RubyTechnicalAnalysis)
      return RubyTechnicalAnalysis::Indicator::Ema.new(period: period).calculate(values).last.to_f
    end
    k = 2.0/(period+1); e=nil; values.each{ |v| e = e ? (v.to_f*k + e*(1-k)) : v.to_f }; e.to_f
  end

  def rsi_last(values, period=14)
    if defined?(TechnicalAnalysis) && TechnicalAnalysis.respond_to?(:rsi)
      return TechnicalAnalysis.rsi(data: values, period: period).last.to_f
    elsif defined?(RubyTechnicalAnalysis)
      return RubyTechnicalAnalysis::Indicator::Rsi.new(period: period).calculate(values).last.to_f
    end
    return 50.0 if values.size < period+1
    g=[]; l=[]; (1...values.size).each{ |i| d=values[i]-values[i-1]; g<<[d,0].max; l<<[-d,0].max }
    ag=g.first(period).sum/period; al=l.first(period).sum/period
    (period...g.size).each{ |i| ag=(ag*(period-1)+g[i])/period; al=(al*(period-1)+l[i])/period }
    rs=al.zero? ? 100.0 : ag/al; 100 - (100/(1+rs))
  end
end