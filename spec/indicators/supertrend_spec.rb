# frozen_string_literal: true

require "spec_helper"

RSpec.describe DhanScalper::Indicators::Supertrend do
  let(:candle_series) do
    series = double("CandleSeries")
    allow(series).to receive(:highs).and_return((1..100).map { |i| 25_000 + (i * 2) })
    allow(series).to receive(:lows).and_return((1..100).map { |i| 25_000 + (i * 2) - 50 })
    allow(series).to receive(:closes).and_return((1..100).map { |i| 25_000 + (i * 2) - 25 })
    series
  end

  let(:supertrend) { described_class.new(series: candle_series, period: 10, multiplier: 3.0) }

  describe "#initialize" do
    it "accepts valid parameters" do
      expect { described_class.new(series: candle_series, period: 10, multiplier: 3.0) }.not_to raise_error
    end

    it "uses default parameters" do
      st = described_class.new(series: candle_series)
      expect(st.instance_variable_get(:@period)).to eq(10)
      expect(st.instance_variable_get(:@multiplier)).to eq(3.0)
    end
  end

  describe "#call" do
    it "calculates supertrend values correctly" do
      result = supertrend.call
      expect(result).to be_an(Array)
      expect(result.length).to eq(100)
      expect(result.compact.all?(Numeric)).to be true
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

    it "handles different multipliers correctly" do
      supertrend_2 = described_class.new(series: candle_series, period: 10, multiplier: 2.0)
      result_2 = supertrend_2.call

      supertrend_4 = described_class.new(series: candle_series, period: 10, multiplier: 4.0)
      result_4 = supertrend_4.call

      expect(result_2.length).to eq(100)
      expect(result_4.length).to eq(100)
      expect(result_2).not_to eq(result_4)
    end

    it "handles edge cases with insufficient data" do
      short_series = double("CandleSeries")
      allow(short_series).to receive(:highs).and_return([25_000])
      allow(short_series).to receive(:lows).and_return([24_950])
      allow(short_series).to receive(:closes).and_return([24_975])

      short_supertrend = described_class.new(series: short_series, period: 10, multiplier: 3.0)
      result = short_supertrend.call
      expect(result).to eq([nil])
    end

    it "returns nil for first few values due to ATR calculation" do
      result = supertrend.call
      # First few values should be nil due to insufficient data for ATR
      expect(result.first(5)).to all(be_nil)
      # Later values should be calculated
      expect(result.last(10).compact).not_to be_empty
    end

    it "produces consistent results for same input" do
      result1 = supertrend.call
      result2 = supertrend.call
      expect(result1).to eq(result2)
    end
  end

  describe "internal calculations" do
    it "produces consistent results for same input" do
      result1 = supertrend.call
      result2 = supertrend.call
      expect(result1).to eq(result2)
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

    it "handles concurrent calculations" do
      threads = []
      results = []

      5.times do |_i|
        threads << Thread.new do
          st = described_class.new(series: candle_series, period: 10, multiplier: 3.0)
          results << st.call
        end
      end

      threads.each(&:join)

      expect(results.length).to eq(5)
      expect(results.all? { |r| r.is_a?(Array) && r.length == 100 }).to be true
    end
  end

  describe "mathematical accuracy" do
    it "produces reasonable supertrend values" do
      result = supertrend.call
      valid_values = result.compact

      expect(valid_values).not_to be_empty
      expect(valid_values.all? { |v| v > 0 }).to be true
      expect(valid_values.all?(Numeric)).to be true
    end

    it "supertrend values follow price trends" do
      result = supertrend.call
      closes = candle_series.closes

      # Compare supertrend with close prices
      result.zip(closes).each do |st, close|
        next if st.nil? || close.nil?

        # Supertrend should be reasonably close to the price
        expect((st - close).abs).to be < (close * 0.1) # Within 10% of price
      end
    end
  end
end
