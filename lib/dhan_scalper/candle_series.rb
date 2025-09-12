# frozen_string_literal: true

require_relative "support/time_zone"
require_relative "candle"
require_relative "indicators/base"
require_relative "indicators/holy_grail"
require_relative "indicators/supertrend"
require_relative "indicators_gate"

module DhanScalper
  class CandleSeries
    include Enumerable

    attr_reader :symbol, :interval, :candles

    def initialize(symbol:, interval: "5")
      @symbol   = symbol
      @interval = interval.to_s
      @candles  = []
    end

    def each(&) = candles.each(&)
    def add_candle(candle) = candles << candle

    # ---------- Loading from DhanHQ ----------
    def self.load_from_dhan_intraday(seg:, sid:, interval:, symbol:)
      target_interval = interval.to_i

      # If 5-minute is requested, fetch 1-minute and aggregate locally to 5-minute
      if target_interval == 5
        rows_1m = fetch_historical_data(seg, sid, "1")
        base = new(symbol: "#{symbol}_1m", interval: "1")
        base.load_from_raw(rows_1m)
        return base.resample_to_minutes(5, symbol: symbol)
      end

      rows = fetch_historical_data(seg, sid, target_interval.to_s)
      series = new(symbol: symbol, interval: target_interval.to_s)
      series.load_from_raw(rows)
      series
    end

    # ---------- Historical Data Fetching ----------
    def self.fetch_historical_data(seg, sid, interval)
      # Check cache first
      cached_data = DhanScalper::Services::HistoricalDataCache.get(seg, sid, interval)
      return cached_data if cached_data

      # Apply rate limiting
      DhanScalper::Services::RateLimiter.wait_if_needed("historical_data")

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
        to_date: to_date,
      }

      attempts = 0
      begin
        result = DhanHQ::Models::HistoricalData.intraday(params)

        if result && (result.is_a?(Array) || result.is_a?(Hash))
          # Cache the result
          DhanScalper::Services::HistoricalDataCache.set(seg, sid, interval, result)
          # Record the request for rate limiting
          DhanScalper::Services::RateLimiter.record_request("historical_data")
          return result
        end
      rescue StandardError => e
        puts "Warning: Failed to fetch historical data: #{e.message}"
        if e.message =~ /DH-904|Too many requests/i && attempts < 2
          attempts += 1
          wait_time = 60 + (attempts * 30) # Progressive backoff: 60s, 90s
          puts "[RATE_LIMIT] Rate limited, waiting #{wait_time}s before retry #{attempts + 1}/2"
          sleep wait_time
          retry
        end
      end

      # Return mock data if method fails (for dryrun/testing)
      puts "Warning: Historical data fetch failed, returning mock data for testing"
      generate_mock_data(seg, sid, interval)
    end

    # Mock data for dryrun/testing when API fails
    def self.generate_mock_data(seg, sid, interval, count = 200)
      puts "[MOCK] Generating mock data for #{seg}_#{sid}_#{interval} (#{count} candles)"

      base_price = case sid.to_s
                   when "13" then 19_500.0  # NIFTY
                   when "25" then 45_000.0  # BANKNIFTY
                   when "1" then 65_000.0   # SENSEX
                   else 20_000.0
                   end

      current_time = Time.now
      candles = []

      count.times do |i|
        # Generate realistic price movement
        price_change = (rand - 0.5) * base_price * 0.01 # ±0.5% change
        open_price = base_price + price_change
        high_price = open_price + (rand * base_price * 0.005) # Up to 0.5% higher
        low_price = open_price - (rand * base_price * 0.005)  # Up to 0.5% lower
        close_price = low_price + (rand * (high_price - low_price))

        candles << {
          timestamp: (current_time - ((count - i) * 60)).to_i, # 1 minute intervals
          open: open_price.round(2),
          high: high_price.round(2),
          low: low_price.round(2),
          close: close_price.round(2),
          volume: rand(1_000..10_000),
        }

        # Update base price for next candle
        base_price = close_price
      end

      candles
    end

    # ---------- Normalization ----------
    def load_from_raw(response)
      normalized = normalise_candles(response)

      normalized.each do |row|
        next if row.nil?

        begin
          @candles << Candle.new(
            ts: to_time(row[:timestamp]),
            open: row[:open], high: row[:high],
            low: row[:low], close: row[:close],
            volume: row[:volume] || 0
          )
        rescue StandardError => e
          puts "[ERROR] Failed to create candle from row: #{e.message}"
          puts "[ERROR] Row data: #{row.inspect}"
        end
      end
      self
    end

    def normalise_candles(resp)
      return [] if resp.nil?

      return [] if resp.respond_to?(:empty?) && resp.empty?

      return resp.map { |c| slice_candle(c) } if resp.is_a?(Array)

      # Columnar hash: { "open"=>[], "high"=>[], ... }
      unless resp.is_a?(Hash) && resp["high"].is_a?(Array)
        puts "[WARNING] Unexpected candle format: #{resp.class}, expected Hash with Array values"
        puts "[WARNING] Response keys: #{resp.keys if resp.respond_to?(:keys)}"
        return []
      end

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
          end.to_i,
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
          volume: candle[:volume] || candle["volume"] || 0,
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

      out = CandleSeries.new(symbol: symbol || "#{@symbol}_#{per}m", interval: per.to_s)
      grouped.keys.sort.each do |ts|
        cols = grouped[ts]
        next if cols.nil? || cols.empty?

        o = cols.first.open
        h = cols.map(&:high).max
        l = cols.map(&:low).min
        c = cols.last.close
        v = cols.sum(&:volume)
        out.add_candle(Candle.new(ts: ts, open: o, high: h, low: l, close: c, volume: v))
      end

      out
    end

    def to_hash
      {
        timestamp: candles.map { |c| c.timestamp.to_i },
        open: opens, high: highs, low: lows, close: closes,
        volume: volumes
      }
    end

    # HL/HLCC arrays for some libs (intrinio)
    def hlc
      candles.map do |c|
        { date_time: DhanScalper::TimeZone.at(c.timestamp || 0), high: c.high, low: c.low, close: c.close }
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

    # ---------- Indicators (using dedicated indicator classes) ----------
    def ema(period = 20)
      DhanScalper::IndicatorsGate.ema_series(closes, period)
    end

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

    def rsi(period = 14)
      DhanScalper::IndicatorsGate.rsi_series(closes, period)
    end

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
      DhanScalper::IndicatorsGate.donchian(hlc, period: period)
    end

    def atr(period = 14)
      DhanScalper::IndicatorsGate.atr(hlc, period: period)
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

    # Supertrend indicator using the dedicated class
    def supertrend(period: 10, multiplier: 2.0)
      return [] if candles.size < period

      DhanScalper::Indicators::Supertrend.new(
        series: self,
        period: period,
        multiplier: multiplier,
      ).call
    end

    # Get the latest Supertrend value
    def supertrend_signal(period: 10, multiplier: 2.0)
      st_values = supertrend(period: period, multiplier: multiplier)
      return :none if st_values.empty? || st_values.last.nil?

      current_price = closes.last
      current_st = st_values.last

      if current_price > current_st
        :bullish
      elsif current_price < current_st
        :bearish
      else
        :neutral
      end
    end

    # Convenience: compute Holy Grail result for this series
    def holy_grail
      DhanScalper::Indicators::HolyGrail.call(candles: to_hash)
    rescue StandardError
      nil
    end

    # Combined signal using multiple indicators
    def combined_signal
      return :none if candles.size < 100

      # Get Holy Grail analysis
      hg = holy_grail
      return :none unless hg&.proceed?

      # Get Supertrend signal
      st_signal = supertrend_signal

      # Combine signals
      case [hg.bias, st_signal]
      when %i[bullish bullish]
        :strong_buy
      when %i[bullish bearish]
        :weak_buy
      when %i[bearish bearish]
        :strong_sell
      when %i[bearish bullish]
        :weak_sell
      else
        :neutral
      end
    end

    private

    def to_time(x) = DhanScalper::TimeZone.parse(x)
  end
end
