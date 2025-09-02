# frozen_string_literal: true

require_relative "candle_series"

class TrendEngine
  def initialize(seg_idx:, sid_idx:)
    @seg_idx = seg_idx
    @sid_idx = sid_idx
  end

  def decide
    c1 = CandleSeries.load_from_dhan_intraday(seg: @seg_idx, sid: @sid_idx, interval: "1", symbol: "INDEX_1m")
    c5 = CandleSeries.load_from_dhan_intraday(seg: @seg_idx, sid: @sid_idx, interval: "5", symbol: "INDEX_5m")
    return :none if c1.candles.size < 50 || c5.candles.size < 50

    ema1_fast = c1.ema(20).last
    ema1_slow = c1.ema(50).last
    rsi1      = c1.rsi(14).last

    ema5_fast = c5.ema(20).last
    ema5_slow = c5.ema(50).last
    rsi5      = c5.rsi(14).last

    up   = (ema1_fast > ema1_slow) && (rsi1 > 55) &&
           (ema5_fast > ema5_slow) && (rsi5 > 52)

    down = (ema1_fast < ema1_slow) && (rsi1 < 45) &&
           (ema5_fast < ema5_slow) && (rsi5 < 48)

    return :long_ce if up
    return :long_pe if down

    :none
  end
end
