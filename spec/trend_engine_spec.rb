# frozen_string_literal: true

require "spec_helper"

RSpec.describe TrendEngine do
  let(:trend_engine) { described_class.new(seg_idx: "IDX_I", sid_idx: "13") }

  before do
    # Mock CandleSeries to avoid actual API calls
    stub_const("CandleSeries", double)
    allow(CandleSeries).to receive(:load_from_dhan_intraday).and_return(mock_candle_series)
  end

  let(:mock_candle_series) do
    double(
      candles: Array.new(60, double), # More than 50 candles
      ema: double(last: 100.0),
      rsi: double(last: 60.0)
    )
  end

  describe "#initialize" do
    it "sets segment and security ID" do
      expect(trend_engine.instance_variable_get(:@seg_idx)).to eq("IDX_I")
      expect(trend_engine.instance_variable_get(:@sid_idx)).to eq("13")
    end
  end

  describe "#decide" do
    context "when sufficient data is available" do
      before do
        # Mock 1-minute data
        allow(CandleSeries).to receive(:load_from_dhan_intraday)
          .with(seg: "IDX_I", sid: "13", interval: "1", symbol: "INDEX_1m")
          .and_return(mock_candle_series)

        # Mock 3-minute data
        allow(CandleSeries).to receive(:load_from_dhan_intraday)
          .with(seg: "IDX_I", sid: "13", interval: "3", symbol: "INDEX_3m")
          .and_return(mock_candle_series)
      end

      context "when trend is bullish" do
        before do
          # Mock bullish indicators
          allow(mock_candle_series).to receive(:ema).with(20).and_return(double(last: 102.0))
          allow(mock_candle_series).to receive(:ema).with(50).and_return(double(last: 98.0))
          allow(mock_candle_series).to receive(:rsi).with(14).and_return(double(last: 60.0))
        end

        it "returns :long_ce for bullish trend" do
          result = trend_engine.decide
          expect(result).to eq(:long_ce)
        end
      end

      context "when trend is bearish" do
        before do
          # Mock bearish indicators
          allow(mock_candle_series).to receive(:ema).with(20).and_return(double(last: 98.0))
          allow(mock_candle_series).to receive(:ema).with(50).and_return(double(last: 102.0))
          allow(mock_candle_series).to receive(:rsi).with(14).and_return(double(last: 40.0))
        end

        it "returns :long_pe for bearish trend" do
          result = trend_engine.decide
          expect(result).to eq(:long_pe)
        end
      end

      context "when trend is neutral" do
        before do
          # Mock neutral indicators
          allow(mock_candle_series).to receive(:ema).with(20).and_return(double(last: 100.0))
          allow(mock_candle_series).to receive(:ema).with(50).and_return(double(last: 100.0))
          allow(mock_candle_series).to receive(:rsi).with(14).and_return(double(last: 50.0))
        end

        it "returns :none for neutral trend" do
          result = trend_engine.decide
          expect(result).to eq(:none)
        end
      end

      context "when 1-minute trend is bullish but 3-minute is neutral" do
        before do
          # Mock mixed indicators
          allow(mock_candle_series).to receive(:ema).with(20).and_return(double(last: 102.0))
          allow(mock_candle_series).to receive(:ema).with(50).and_return(double(last: 98.0))
          allow(mock_candle_series).to receive(:rsi).with(14).and_return(double(last: 60.0))
        end

        it "returns :none when 3-minute trend doesn't confirm" do
          result = trend_engine.decide
          expect(result).to eq(:none)
        end
      end

      context "when 3-minute trend is bearish but 1-minute is neutral" do
        before do
          # Mock mixed indicators
          allow(mock_candle_series).to receive(:ema).with(20).and_return(double(last: 100.0))
          allow(mock_candle_series).to receive(:ema).with(50).and_return(double(last: 100.0))
          allow(mock_candle_series).to receive(:rsi).with(14).and_return(double(last: 50.0))
        end

        it "returns :none when 1-minute trend doesn't confirm" do
          result = trend_engine.decide
          expect(result).to eq(:none)
        end
      end
    end

    context "when insufficient data is available" do
      before do
        short_series = double(candles: Array.new(30, double)) # Less than 50 candles

        allow(CandleSeries).to receive(:load_from_dhan_intraday)
          .with(seg: "IDX_I", sid: "13", interval: "1", symbol: "INDEX_1m")
          .and_return(short_series)

        allow(CandleSeries).to receive(:load_from_dhan_intraday)
          .with(seg: "IDX_I", sid: "13", interval: "3", symbol: "INDEX_3m")
          .and_return(mock_candle_series)
      end

      it "returns :none when 1-minute data is insufficient" do
        result = trend_engine.decide
        expect(result).to eq(:none)
      end
    end

    context "when 3-minute data is insufficient" do
      before do
        short_series = double(candles: Array.new(30, double)) # Less than 50 candles

        allow(CandleSeries).to receive(:load_from_dhan_intraday)
          .with(seg: "IDX_I", sid: "13", interval: "1", symbol: "INDEX_1m")
          .and_return(mock_candle_series)

        allow(CandleSeries).to receive(:load_from_dhan_intraday)
          .with(seg: "IDX_I", sid: "13", interval: "3", symbol: "INDEX_3m")
          .and_return(short_series)
      end

      it "returns :none when 3-minute data is insufficient" do
        result = trend_engine.decide
        expect(result).to eq(:none)
      end
    end

    context "edge cases" do
      it "handles RSI at boundary values" do
        allow(CandleSeries).to receive(:load_from_dhan_intraday).and_return(mock_candle_series)

        # Test RSI at 55 (boundary for bullish)
        allow(mock_candle_series).to receive(:ema).with(20).and_return(double(last: 102.0))
        allow(mock_candle_series).to receive(:ema).with(50).and_return(double(last: 98.0))
        allow(mock_candle_series).to receive(:rsi).with(14).and_return(double(last: 55.0))

        result = trend_engine.decide
        expect(result).to eq(:long_ce)
      end

      it "handles RSI at 45 (boundary for bearish)" do
        allow(CandleSeries).to receive(:load_from_dhan_intraday).and_return(mock_candle_series)

        # Test RSI at 45 (boundary for bearish)
        allow(mock_candle_series).to receive(:ema).with(20).and_return(double(last: 98.0))
        allow(mock_candle_series).to receive(:ema).with(50).and_return(double(last: 102.0))
        allow(mock_candle_series).to receive(:rsi).with(14).and_return(double(last: 45.0))

        result = trend_engine.decide
        expect(result).to eq(:long_pe)
      end

      it "handles equal EMA values" do
        allow(CandleSeries).to receive(:load_from_dhan_intraday).and_return(mock_candle_series)

        # Test when fast and slow EMAs are equal
        allow(mock_candle_series).to receive(:ema).with(20).and_return(double(last: 100.0))
        allow(mock_candle_series).to receive(:ema).with(50).and_return(double(last: 100.0))
        allow(mock_candle_series).to receive(:rsi).with(14).and_return(double(last: 60.0))

        result = trend_engine.decide
        expect(result).to eq(:none)
      end
    end

    context "error handling" do
      it "handles CandleSeries loading errors gracefully" do
        allow(CandleSeries).to receive(:load_from_dhan_intraday).and_raise(StandardError, "API Error")

        result = trend_engine.decide
        expect(result).to eq(:none)
      end

      it "handles nil candle series" do
        allow(CandleSeries).to receive(:load_from_dhan_intraday).and_return(nil)

        result = trend_engine.decide
        expect(result).to eq(:none)
      end
    end
  end

  describe "trend logic validation" do
    before do
      allow(CandleSeries).to receive(:load_from_dhan_intraday).and_return(mock_candle_series)
    end

    it "requires both timeframes to be bullish for long_ce" do
      # 1-minute bullish
      allow(mock_candle_series).to receive(:ema).with(20).and_return(double(last: 102.0))
      allow(mock_candle_series).to receive(:ema).with(50).and_return(double(last: 98.0))
      allow(mock_candle_series).to receive(:rsi).with(14).and_return(double(last: 60.0))

      # 3-minute also bullish
      allow(mock_candle_series).to receive(:ema).with(20).and_return(double(last: 101.0))
      allow(mock_candle_series).to receive(:ema).with(50).and_return(double(last: 99.0))
      allow(mock_candle_series).to receive(:rsi).with(14).and_return(double(last: 55.0))

      result = trend_engine.decide
      expect(result).to eq(:long_ce)
    end

    it "requires both timeframes to be bearish for long_pe" do
      # 1-minute bearish
      allow(mock_candle_series).to receive(:ema).with(20).and_return(double(last: 98.0))
      allow(mock_candle_series).to receive(:ema).with(50).and_return(double(last: 102.0))
      allow(mock_candle_series).to receive(:rsi).with(14).and_return(double(last: 40.0))

      # 3-minute also bearish
      allow(mock_candle_series).to receive(:ema).with(20).and_return(double(last: 99.0))
      allow(mock_candle_series).to receive(:ema).with(50).and_return(double(last: 101.0))
      allow(mock_candle_series).to receive(:rsi).with(14).and_return(double(last: 48.0))

      result = trend_engine.decide
      expect(result).to eq(:long_pe)
    end
  end
end
