# frozen_string_literal: true

require_relative "candle_series"

class TrendEngine
  def initialize(seg_idx:, sid_idx:)
    @seg_idx = seg_idx
    @sid_idx = sid_idx
  end

  def decide
    c1 = CandleSeries.load_from_dhan_intraday(seg: @seg_idx, sid: @sid_idx, interval: "1", symbol: "INDEX_1m")
    c3 = CandleSeries.load_from_dhan_intraday(seg: @seg_idx, sid: @sid_idx, interval: "3", symbol: "INDEX_3m")
    return :none if c1.candles.size < 50 || c3.candles.size < 50

    ema1_fast = c1.ema(20).last
    ema1_slow = c1.ema(50).last
    rsi1      = c1.rsi(14).last

    ema3_fast = c3.ema(20).last
    ema3_slow = c3.ema(50).last
    rsi3      = c3.rsi(14).last

    up   = (ema1_fast > ema1_slow) && (rsi1 > 55) &&
           (ema3_fast > ema3_slow) && (rsi3 > 52)

    down = (ema1_fast < ema1_slow) && (rsi1 < 45) &&
           (ema3_fast < ema3_slow) && (rsi3 < 48)

    return :long_ce if up
    return :long_pe if down

    :none
  end
end
