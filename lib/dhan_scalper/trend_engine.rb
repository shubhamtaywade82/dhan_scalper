module DhanScalper
  class TrendEngine
    def initialize(seg_idx:, sid_idx:) = (@seg_idx, @sid_idx = seg_idx, sid_idx)
    def decide
      c1 = Bars.c1(seg: @seg_idx, sid: @sid_idx); c3 = Bars.c3(seg: @seg_idx, sid: @sid_idx)
      return :none if c1.size < 50 || c3.size < 50
      e1f=Indicators.ema_last(c1,20); e1s=Indicators.ema_last(c1,50); r1=Indicators.rsi_last(c1,14)
      e3f=Indicators.ema_last(c3,20); e3s=Indicators.ema_last(c3,50); r3=Indicators.rsi_last(c3,14)
      return :long_ce if (e1f>e1s && r1>55) && (e3f>e3s && r3>52)
      return :long_pe if (e1f<e1s && r1<45) && (e3f<e3s && r3<48)
      :none
    end
  end
end