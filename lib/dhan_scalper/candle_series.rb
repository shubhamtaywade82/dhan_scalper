# frozen_string_literal: true

require_relative "support/time_zone"
require_relative "candle"

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
    values.map { |v| e = e.nil? ? v.to_f : (v.to_f * k + e * (1 - k)) }
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
      ag = (ag * (period - 1) + gains[i]) / period
      al = (al * (period - 1) + losses[i]) / period
      rs = al.zero? ? 100.0 : ag / al
      out << (100 - (100 / (1 + rs)))
    end
    out.unshift(*Array.new(values.size - out.size, 50.0))
    out
  end

  # Optional: simple Supertrend (only if you have a lib; otherwise return [])
  def supertrend_series(series)
    if defined?(Indicators) && Indicators.respond_to?(:Supertrend)
      return Indicators::Supertrend.new(series: series).call
    end

    [] # stub until you wire a concrete impl
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
      # intrinio returns array of hashes with :atr keys (depending on version)
      res = begin
        TechnicalAnalysis.atr(values_hlc, period: period)
      rescue StandardError
        []
      end
      return res
    end
    []
  end
end

class CandleSeries
  include Enumerable

  attr_reader :symbol, :interval, :candles

  def initialize(symbol:, interval: "5")
    @symbol   = symbol
    @interval = interval.to_s
    @candles  = []
  end

  def each(&blk) = candles.each(&blk)
  def add_candle(candle) = candles << candle

  # ---------- Loading from DhanHQ ----------
  def self.load_from_dhan_intraday(seg:, sid:, interval:, symbol:)
    target_interval = interval.to_i

    # If 3-minute is requested, fetch 1-minute and aggregate locally to 3-minute
    if target_interval == 3
      puts "[DEBUG] Aggregating 1m candles to 3m for sid=#{sid}"
      rows_1m = fetch_historical_data(seg, sid, "1")
      base = new(symbol: "#{symbol}_1m", interval: "1")
      base.load_from_raw(rows_1m)
      return base.resample_to_minutes(3, symbol: symbol)
    end

    rows = fetch_historical_data(seg, sid, target_interval.to_s)
    series = new(symbol: symbol, interval: target_interval.to_s)
    series.load_from_raw(rows)
    series
  end

  # ---------- Historical Data Fetching ----------
  def self.fetch_historical_data(seg, sid, interval)
    puts "[DEBUG] Attempting to fetch historical data for seg=#{seg}, sid=#{sid}, interval=#{interval}"

    # Calculate date range (last 7 days for intraday data)
    to_date = Date.today.strftime("%Y-%m-%d")
    from_date = (Date.today - 7).strftime("%Y-%m-%d")

    # Prepare parameters for DhanHQ API
    params = {
      security_id: sid.to_s,  # This should be the actual security ID (e.g., "13" for NIFTY)
      exchange_segment: seg,  # This should be the segment (e.g., "IDX_I")
      instrument: (seg == "IDX_I" ? "INDEX" : "OPTION"),
      interval: interval.to_s,
      from_date: from_date,
      to_date: to_date
    }

    begin
      puts "[DEBUG] Calling DhanHQ::Models::HistoricalData.intraday with params: #{params}"
      result = DhanHQ::Models::HistoricalData.intraday(params)
      puts "[DEBUG] Historical data result: #{result.class} - #{result.respond_to?(:size) ? "size: #{result.size}" : "keys: #{result.keys if result.respond_to?(:keys)}"}"
      return result if result && (result.is_a?(Array) || result.is_a?(Hash))
    rescue StandardError => e
      puts "Warning: Failed to fetch historical data: #{e.message}"
    end

    # Return empty array if method fails
    puts "Warning: Historical data fetch failed, returning empty data"
    []
  end

  # ---------- Normalization ----------
  def load_from_raw(response)
    normalise_candles(response).each do |row|
      @candles << Candle.new(
        ts: to_time(row[:timestamp]),
        open: row[:open], high: row[:high],
        low: row[:low], close: row[:close],
        volume: row[:volume] || 0
      )
    end
    self
  end

  def normalise_candles(resp)
    return [] if resp.nil? || (resp.respond_to?(:empty?) && resp.empty?)
    return resp.map { |c| slice_candle(c) } if resp.is_a?(Array)

    # Columnar hash: { "open"=>[], "high"=>[], ... }
    raise "Unexpected candle format: #{resp.class}" unless resp.is_a?(Hash) && resp["high"].is_a?(Array)

    size = resp["high"].size
    (0...size).map do |i|
      {
        open: resp["open"][i].to_f,
        close: resp["close"][i].to_f,
        high: resp["high"][i].to_f,
        low: resp["low"][i].to_f,
        timestamp: to_time(resp["timestamp"][i]),
        volume: begin
          resp["volume"][i]
        rescue StandardError
          0
        end.to_i
      }
    end
  end

  # Accept a single row as hash or [ts, o, h, l, c, v]
  def slice_candle(candle)
    if candle.is_a?(Hash)
      {
        open: candle[:open] || candle["open"],
        close: candle[:close] || candle["close"],
        high: candle[:high] || candle["high"],
        low: candle[:low] || candle["low"],
        timestamp: to_time(candle[:timestamp] || candle["timestamp"]),
        volume: candle[:volume] || candle["volume"] || 0
      }
    elsif candle.respond_to?(:[]) && candle.size >= 5
      {
        timestamp: to_time(candle[0]),
        open: candle[1], high: candle[2], low: candle[3], close: candle[4],
        volume: candle[5] || 0
      }
    else
      raise "Unexpected candle format: #{candle.inspect}"
    end
  end

  # ---------- Accessors ----------
  def opens  = candles.map(&:open)
  def closes = candles.map(&:close)
  def highs  = candles.map(&:high)
  def lows   = candles.map(&:low)
  def volumes = candles.map(&:volume)

  # ---------- Resampling ----------
  # Build higher timeframe candles from this series (assumes minute-based input)
  def resample_to_minutes(period, symbol: nil)
    per = period.to_i
    raise ArgumentError, "period must be > 1" unless per > 1
    return self if @interval.to_i == per

    bucket_seconds = per * 60
    grouped = {}

    # Ensure candles are sorted by timestamp
    sorted = candles.sort_by { |c| c.timestamp.to_i }

    sorted.each do |c|
      bucket_start = Time.at((c.timestamp.to_i / bucket_seconds) * bucket_seconds)
      (grouped[bucket_start] ||= []) << c
    end

    out = CandleSeries.new(symbol: (symbol || "#{@symbol}_#{per}m"), interval: per.to_s)
    grouped.keys.sort.each do |ts|
      cols = grouped[ts]
      next if cols.nil? || cols.empty?

      o = cols.first.open
      h = cols.map(&:high).max
      l = cols.map(&:low).min
      c = cols.last.close
      v = cols.map(&:volume).sum
      out.add_candle(Candle.new(ts: ts, open: o, high: h, low: l, close: c, volume: v))
    end

    out
  end

  def to_hash
    {
      "timestamp" => candles.map { |c| c.timestamp.to_i },
      "open" => opens, "high" => highs, "low" => lows, "close" => closes,
      "volume" => volumes
    }
  end

  # HL/HLCC arrays for some libs (intrinio)
  def hlc
    candles.map do |c|
      { date_time: TimeZone.at(c.timestamp || 0), high: c.high, low: c.low, close: c.close }
    end
  end

  # ---------- Pattern helpers ----------
  def swing_high?(i, lookback = 2)
    return false if i < lookback || i + lookback >= candles.size

    cur = candles[i].high
    left  = candles[(i - lookback)...i].map(&:high)
    right = candles[(i + 1)..(i + lookback)].map(&:high)
    cur > left.max && cur > right.max
  end

  def swing_low?(i, lookback = 2)
    return false if i < lookback || i + lookback >= candles.size

    cur = candles[i].low
    left  = candles[(i - lookback)...i].map(&:low)
    right = candles[(i + 1)..(i + lookback)].map(&:low)
    cur < left.min && cur < right.min
  end

  def inside_bar?(i)
    return false if i < 1

    cur = candles[i]
    prev = candles[i - 1]
    cur.high < prev.high && cur.low > prev.low
  end

  # ---------- Indicators (safe calls via IndicatorsGate) ----------
  def ema(period = 20) = IndicatorsGate.ema_series(closes, period)

  def sma(period = 20)
    cs = closes
    return [] if cs.empty?

    win = []
    out = []
    cs.each do |v|
      win << v
      win.shift if win.size > period
      out << (win.sum / win.size.to_f)
    end
    out
  end

  def rsi(period = 14) = IndicatorsGate.rsi_series(closes, period)

  def macd(fast = 12, slow = 26, signal = 9)
    if defined?(RubyTechnicalAnalysis)
      macd = RubyTechnicalAnalysis::Macd.new(series: closes, fast_period: fast, slow_period: slow,
                                             signal_period: signal)
      return macd.call
    end
    [] # optional
  end

  def bollinger_bands(period: 20)
    return nil if closes.size < period

    if defined?(RubyTechnicalAnalysis)
      bb = RubyTechnicalAnalysis::BollingerBands.new(series: closes, period: period).call
      return { upper: bb[0], lower: bb[1], middle: bb[2] }
    end
    nil
  end

  def donchian_channel(period: 20)
    IndicatorsGate.donchian(hlc, period: period)
  end

  def atr(period = 14)
    IndicatorsGate.atr(hlc, period: period)
  end

  def rate_of_change(period = 5)
    cs = closes
    return [] if cs.size < period + 1

    cs.each_index.map do |i|
      if i < period
        nil
      else
        prev = cs[i - period].to_f
        prev.zero? ? nil : ((cs[i].to_f - prev) / prev) * 100.0
      end
    end
  end

  # Simple supertrend signal (requires an implementation/library; otherwise nil)
  def supertrend_signal
    line = IndicatorsGate.supertrend_series(self)
    return nil if line.nil? || line.empty?

    latest_close = closes.last
    st = line.last
    return :long_entry  if latest_close > st
    return :short_entry if latest_close < st

    nil
  end

  private

  def to_time(x) = TimeZone.parse(x)
end
