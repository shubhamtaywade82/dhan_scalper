# frozen_string_literal: true

require "spec_helper"

RSpec.describe DhanScalper::Indicators::HolyGrail, :unit do
  let(:candle_data) do
    {
      timestamps: (1..200).map { |i| Time.now - ((200 - i) * 60) },
      opens: (1..200).map { |_i| rand(24_900..25_100) },
      highs: (1..200).map { |_i| rand(25_050..25_150) },
      lows: (1..200).map { |_i| rand(24_850..24_950) },
      closes: (1..200).map { |_i| rand(24_950..25_050) },
      volumes: (1..200).map { |_i| rand(1_000..10_000) },
    }
  end

  let(:holy_grail) { described_class.new(candles: candle_data) }

  describe "#call" do
    context "with bullish market conditions" do
      before do
        # Create bullish candle data
        bullish_closes = (1..200).map { |i| 25_000 + (i * 2) } # Upward trend
        bullish_highs = bullish_closes.map { |c| c + rand(10..30) }
        bullish_lows = bullish_closes.map { |c| c - rand(5..15) }

        candle_data[:closes] = bullish_closes
        candle_data[:highs] = bullish_highs
        candle_data[:lows] = bullish_lows
      end

      it "identifies bullish bias correctly" do
        result = holy_grail.call
        expect(result[:bias]).to eq(:bullish)
      end

      it "shows strong momentum" do
        result = holy_grail.call
        expect(result[:momentum]).to eq(:strong)
      end

      it "has high ADX indicating strong trend" do
        result = holy_grail.call
        expect(result[:adx]).to be > 25
      end

      it "shows bullish RSI" do
        result = holy_grail.call
        expect(result[:rsi]).to be > 50
      end

      it "indicates bullish MACD" do
        result = holy_grail.call
        expect(result[:macd]).to eq(:bullish)
      end
    end

    context "with bearish market conditions" do
      before do
        # Create bearish candle data
        bearish_closes = (1..200).map { |i| 25_000 - (i * 2) } # Downward trend
        bearish_highs = bearish_closes.map { |c| c + rand(5..15) }
        bearish_lows = bearish_closes.map { |c| c - rand(10..30) }

        candle_data[:closes] = bearish_closes
        candle_data[:highs] = bearish_highs
        candle_data[:lows] = bearish_lows
      end

      it "identifies bearish bias correctly" do
        result = holy_grail.call
        expect(result[:bias]).to eq(:bearish)
      end

      it "shows strong momentum" do
        result = holy_grail.call
        expect(result[:momentum]).to eq(:strong)
      end

      it "has high ADX indicating strong trend" do
        result = holy_grail.call
        expect(result[:adx]).to be > 25
      end

      it "shows bearish RSI" do
        result = holy_grail.call
        expect(result[:rsi]).to be < 50
      end

      it "indicates bearish MACD" do
        result = holy_grail.call
        expect(result[:macd]).to eq(:bearish)
      end
    end

    context "with sideways market conditions" do
      before do
        # Create sideways candle data
        sideways_closes = (1..200).map { |i| 25_000 + (Math.sin(i * 0.1) * 50) } # Sideways oscillation
        sideways_highs = sideways_closes.map { |c| c + rand(5..20) }
        sideways_lows = sideways_closes.map { |c| c - rand(5..20) }

        candle_data[:closes] = sideways_closes
        candle_data[:highs] = sideways_highs
        candle_data[:lows] = sideways_lows
      end

      it "identifies neutral bias" do
        result = holy_grail.call
        expect(result[:bias]).to eq(:neutral)
      end

      it "shows weak momentum" do
        result = holy_grail.call
        expect(result[:momentum]).to eq(:weak)
      end

      it "has low ADX indicating weak trend" do
        result = holy_grail.call
        expect(result[:adx]).to be < 25
      end

      it "shows neutral RSI" do
        result = holy_grail.call
        expect(result[:rsi]).to be_between(40, 60)
      end

      it "indicates neutral MACD" do
        result = holy_grail.call
        expect(result[:macd]).to eq(:neutral)
      end
    end

    context "with insufficient data" do
      let(:insufficient_data) do
        {
          timestamps: (1..50).map { |i| Time.now - ((50 - i) * 60) },
          opens: (1..50).map { |_i| rand(24_900..25_100) },
          highs: (1..50).map { |_i| rand(25_050..25_150) },
          lows: (1..50).map { |_i| rand(24_850..24_950) },
          closes: (1..50).map { |_i| rand(24_950..25_050) },
          volumes: (1..50).map { |_i| rand(1_000..10_000) },
        }
      end

      it "returns nil for insufficient data" do
        holy_grail_insufficient = described_class.new(candles: insufficient_data)
        result = holy_grail_insufficient.call
        expect(result).to be_nil
      end
    end

    context "with edge cases" do
      it "handles zero values gracefully" do
        zero_data = candle_data.dup
        zero_data[:closes] = [0] * 200
        zero_data[:highs] = [0] * 200
        zero_data[:lows] = [0] * 200

        holy_grail_zero = described_class.new(candles: zero_data)
        expect { holy_grail_zero.call }.not_to raise_error
      end

      it "handles negative values gracefully" do
        negative_data = candle_data.dup
        negative_data[:closes] = (1..200).map { |i| -i }
        negative_data[:highs] = (1..200).map { |i| -i + 10 }
        negative_data[:lows] = (1..200).map { |i| -i - 10 }

        holy_grail_negative = described_class.new(candles: negative_data)
        expect { holy_grail_negative.call }.not_to raise_error
      end

      it "handles very large values" do
        large_data = candle_data.dup
        large_data[:closes] = (1..200).map { |i| 1_000_000 + i }
        large_data[:highs] = (1..200).map { |i| 1_000_000 + i + 100 }
        large_data[:lows] = (1..200).map { |i| 1_000_000 + i - 100 }

        holy_grail_large = described_class.new(candles: large_data)
        expect { holy_grail_large.call }.not_to raise_error
      end
    end
  end

  describe "#generate_options_signal" do
    it "generates bullish signal for strong bullish indicators" do
      signal, strength = holy_grail.send(:generate_options_signal, :bullish, :strong, 30.0, 70.0, :bullish)
      expect(signal).to eq(:bullish)
      expect(strength).to be > 0.7
    end

    it "generates bearish signal for strong bearish indicators" do
      signal, strength = holy_grail.send(:generate_options_signal, :bearish, :strong, 30.0, 30.0, :bearish)
      expect(signal).to eq(:bearish)
      expect(strength).to be > 0.7
    end

    it "generates weak signal for mixed indicators" do
      signal, strength = holy_grail.send(:generate_options_signal, :bullish, :weak, 15.0, 50.0, :neutral)
      expect(signal).to eq(:none)
      expect(strength).to be < 0.5
    end

    it "handles edge cases in signal generation" do
      # Test with extreme values
      signal, strength = holy_grail.send(:generate_options_signal, :bullish, :strong, 50.0, 90.0, :bullish)
      expect(signal).to eq(:bullish)
      expect(strength).to be_between(0.0, 1.0)
    end
  end

  describe "performance characteristics" do
    it "processes large datasets efficiently" do
      large_candle_data = {
        timestamps: (1..1_000).map { |i| Time.now - ((1_000 - i) * 60) },
        opens: (1..1_000).map { |_i| rand(24_900..25_100) },
        highs: (1..1_000).map { |_i| rand(25_050..25_150) },
        lows: (1..1_000).map { |_i| rand(24_850..24_950) },
        closes: (1..1_000).map { |_i| rand(24_950..25_050) },
        volumes: (1..1_000).map { |_i| rand(1_000..10_000) },
      }

      large_holy_grail = described_class.new(candles: large_candle_data)

      start_time = Time.now
      result = large_holy_grail.call
      duration = Time.now - start_time

      expect(duration).to be < 1.0 # Should complete within 1 second
      expect(result).not_to be_nil
    end

    it "handles concurrent calculations" do
      threads = []
      results = []

      10.times do |_i|
        threads << Thread.new do
          holy_grail_instance = described_class.new(candles: candle_data)
          results << holy_grail_instance.call
        end
      end

      threads.each(&:join)

      expect(results.length).to eq(10)
      expect(results.all? { |r| r.is_a?(Hash) }).to be true
    end
  end
end

RSpec.describe DhanScalper::Indicators::Supertrend, :unit do
  let(:candle_series) do
    series = double("CandleSeries")
    allow(series).to receive(:highs).and_return((1..100).map { |i| 25_000 + (i * 2) })
    allow(series).to receive(:lows).and_return((1..100).map { |i| 25_000 + (i * 2) - 50 })
    allow(series).to receive(:closes).and_return((1..100).map { |i| 25_000 + (i * 2) - 25 })
    series
  end

  let(:supertrend) { described_class.new(series: candle_series, period: 10, multiplier: 3.0) }

  describe "#call" do
    it "calculates supertrend values correctly" do
      result = supertrend.call
      expect(result).to be_an(Array)
      expect(result.length).to eq(100)
      expect(result.all? { |v| v.is_a?(Numeric) }).to be true
    end

    it "handles different periods correctly" do
      supertrend_5 = described_class.new(series: candle_series, period: 5, multiplier: 2.0)
      result_5 = supertrend_5.call

      supertrend_20 = described_class.new(series: candle_series, period: 20, multiplier: 4.0)
      result_20 = supertrend_20.call

      expect(result_5.length).to eq(100)
      expect(result_20.length).to eq(100)
      expect(result_5).not_to eq(result_20)
    end

    it "handles edge cases" do
      # Test with insufficient data
      short_series = double("CandleSeries")
      allow(short_series).to receive(:highs).and_return([25_000])
      allow(short_series).to receive(:lows).and_return([24_950])
      allow(short_series).to receive(:closes).and_return([24_975])

      short_supertrend = described_class.new(series: short_series, period: 10, multiplier: 3.0)
      result = short_supertrend.call
      expect(result).to eq([])
    end
  end

  describe "performance" do
    it "calculates efficiently for large datasets" do
      large_series = double("CandleSeries")
      allow(large_series).to receive(:highs).and_return((1..1_000).map { |i| 25_000 + i })
      allow(large_series).to receive(:lows).and_return((1..1_000).map { |i| 25_000 + i - 50 })
      allow(large_series).to receive(:closes).and_return((1..1_000).map { |i| 25_000 + i - 25 })

      large_supertrend = described_class.new(series: large_series, period: 20, multiplier: 3.0)

      start_time = Time.now
      result = large_supertrend.call
      duration = Time.now - start_time

      expect(duration).to be < 0.5 # Should complete within 0.5 seconds
      expect(result.length).to eq(1_000)
    end
  end
end

RSpec.describe DhanScalper::CandleSeries, :unit do
  let(:candle_data) do
    {
      timestamps: (1..100).map { |i| Time.now - ((100 - i) * 60) },
      opens: (1..100).map { |_i| rand(24_950..25_050) },
      highs: (1..100).map { |_i| rand(25_000..25_100) },
      lows: (1..100).map { |_i| rand(24_900..25_000) },
      closes: (1..100).map { |_i| rand(24_975..25_025) },
      volumes: (1..100).map { |_i| rand(1_000..10_000) },
    }
  end

  let(:candle_series) { described_class.new(symbol: "NIFTY", interval: "1m") }

  before do
    allow(candle_series).to receive(:candles).and_return(
      candle_data[:timestamps].zip(
        candle_data[:opens],
        candle_data[:highs],
        candle_data[:lows],
        candle_data[:closes],
        candle_data[:volumes],
      ).map do |ts, o, h, l, c, v|
        DhanScalper::Candle.new(ts: ts, open: o, high: h, low: l, close: c, volume: v)
      end,
    )
  end

  describe "#holy_grail" do
    it "returns holy grail analysis" do
      result = candle_series.holy_grail
      expect(result).to be_a(Hash)
      expect(result).to include(:bias, :momentum, :adx, :rsi, :macd)
    end
  end

  describe "#supertrend_signal" do
    it "returns supertrend signal" do
      result = candle_series.supertrend_signal
      expect(result).to be_in(%i[bullish bearish none])
    end
  end

  describe "#combined_signal" do
    it "combines multiple signals correctly" do
      result = candle_series.combined_signal
      expect(result).to be_in(%i[bullish bearish none])
    end
  end

  describe "#sma" do
    it "calculates simple moving average" do
      result = candle_series.sma(20)
      expect(result).to be_an(Array)
      expect(result.length).to eq(100)
    end
  end

  describe "#rsi" do
    it "calculates RSI" do
      result = candle_series.rsi(14)
      expect(result).to be_an(Array)
      expect(result.length).to eq(100)
      expect(result.all? { |v| v.between?(0, 100) }).to be true
    end
  end

  describe "#macd" do
    it "calculates MACD" do
      result = candle_series.macd(12, 26, 9)
      expect(result).to be_a(Hash)
      expect(result).to include(:macd_line, :signal_line, :histogram)
    end
  end

  describe "#bollinger_bands" do
    it "calculates Bollinger Bands" do
      result = candle_series.bollinger_bands(period: 20)
      expect(result).to be_a(Hash)
      expect(result).to include(:upper, :middle, :lower)
    end
  end

  describe "#atr" do
    it "calculates Average True Range" do
      result = candle_series.atr(14)
      expect(result).to be_an(Array)
      expect(result.length).to eq(100)
      expect(result.all? { |v| v >= 0 }).to be true
    end
  end

  describe "performance characteristics" do
    it "handles large datasets efficiently" do
      large_candle_data = {
        timestamps: (1..1_000).map { |i| Time.now - ((1_000 - i) * 60) },
        opens: (1..1_000).map { |_i| rand(24_950..25_050) },
        highs: (1..1_000).map { |_i| rand(25_000..25_100) },
        lows: (1..1_000).map { |_i| rand(24_900..25_000) },
        closes: (1..1_000).map { |_i| rand(24_975..25_025) },
        volumes: (1..1_000).map { |_i| rand(1_000..10_000) },
      }

      large_series = described_class.new(symbol: "NIFTY", interval: "1m")
      allow(large_series).to receive(:candles).and_return(
        large_candle_data[:timestamps].zip(
          large_candle_data[:opens],
          large_candle_data[:highs],
          large_candle_data[:lows],
          large_candle_data[:closes],
          large_candle_data[:volumes],
        ).map do |ts, o, h, l, c, v|
          DhanScalper::Candle.new(ts: ts, open: o, high: h, low: l, close: c, volume: v)
        end,
      )

      start_time = Time.now
      large_series.holy_grail
      large_series.supertrend_signal
      large_series.sma(20)
      large_series.rsi(14)
      duration = Time.now - start_time

      expect(duration).to be < 2.0 # Should complete within 2 seconds
    end
  end
end
