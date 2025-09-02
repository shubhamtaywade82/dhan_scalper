# frozen_string_literal: true

require "spec_helper"

RSpec.describe CandleSeries do
  let(:series) { described_class.new(symbol: "NIFTY", interval: "5") }

  before do
    # Mock DhanHQ classes
    stub_const("DhanHQ::Models::HistoricalData", double)
    stub_const("DhanHQ::HistoricalData", double)
    stub_const("DhanHQ::Models::Candles", double)
    stub_const("DhanHQ::Candles", double)

    # Mock TimeZone
    stub_const("TimeZone", double)
    allow(TimeZone).to receive_messages(parse: Time.now, at: Time.now)
  end

  describe "#initialize" do
    it "sets instance variables correctly" do
      expect(series.symbol).to eq("NIFTY")
      expect(series.interval).to eq("5")
      expect(series.candles).to eq([])
    end

    it "converts interval to string" do
      series = described_class.new(symbol: "NIFTY", interval: 5)
      expect(series.interval).to eq("5")
    end
  end

  describe "#each" do
    it "delegates to candles array" do
      expect(series.candles).to receive(:each)
      series.each { |c| }
    end
  end

  describe "#add_candle" do
    let(:candle) { double("Candle") }

    it "adds candle to candles array" do
      series.add_candle(candle)
      expect(series.candles).to include(candle)
    end
  end

  describe ".load_from_dhan_intraday" do
    let(:mock_series) { double("CandleSeries") }
    let(:mock_data) { [{ timestamp: Time.now.to_i, open: 100.0, high: 105.0, low: 98.0, close: 103.0, volume: 1000 }] }

    before do
      allow(mock_series).to receive(:load_from_raw).and_return(mock_series)
      allow(described_class).to receive_messages(new: mock_series, fetch_historical_data: mock_data)
    end

    it "creates new series and loads data" do
      result = described_class.load_from_dhan_intraday(
        seg: "IDX_I",
        sid: "13",
        interval: "5",
        symbol: "INDEX"
      )

      expect(described_class).to have_received(:new).with(symbol: "INDEX", interval: "5")
      expect(described_class).to have_received(:fetch_historical_data).with("IDX_I", "13", "5")
      expect(mock_series).to have_received(:load_from_raw).with(mock_data)
      expect(result).to eq(mock_series)
    end
  end

  describe ".fetch_historical_data" do
    let(:seg) { "IDX_I" }
    let(:sid) { "13" }
    let(:interval) { "5" }

    context "when first method succeeds" do
      let(:mock_data) do
        [{ timestamp: Time.now.to_i, open: 100.0, high: 105.0, low: 98.0, close: 103.0, volume: 1000 }]
      end

      before do
        allow(DhanHQ::Models::HistoricalData).to receive(:intraday).and_return(mock_data)
      end

      it "returns data from first method" do
        result = described_class.fetch_historical_data(seg, sid, interval)
        expect(result).to eq(mock_data)
      end

      it "calls first method with correct parameters" do
        described_class.fetch_historical_data(seg, sid, interval)
        expect(DhanHQ::Models::HistoricalData).to have_received(:intraday).with(
          security_id: "13",
          exchange_segment: "IDX_I",
          instrument: "INDEX",
          interval: "5"
        )
      end
    end

    context "when first method fails, second succeeds" do
      let(:mock_data) do
        [{ timestamp: Time.now.to_i, open: 100.0, high: 105.0, low: 98.0, close: 103.0, volume: 1000 }]
      end

      before do
        allow(DhanHQ::Models::HistoricalData).to receive(:intraday).and_raise(StandardError, "Failed")
        allow(DhanHQ::HistoricalData).to receive(:intraday).and_return(mock_data)
      end

      it "falls back to second method" do
        result = described_class.fetch_historical_data(seg, sid, interval)
        expect(result).to eq(mock_data)
      end
    end

    context "when first two methods fail, third succeeds" do
      let(:mock_data) do
        [{ timestamp: Time.now.to_i, open: 100.0, high: 105.0, low: 98.0, close: 103.0, volume: 1000 }]
      end

      before do
        allow(DhanHQ::Models::HistoricalData).to receive(:intraday).and_raise(StandardError, "Failed")
        allow(DhanHQ::HistoricalData).to receive(:intraday).and_raise(StandardError, "Failed")
        allow(DhanHQ::Models::HistoricalData).to receive(:fetch).and_return(mock_data)
      end

      it "falls back to third method" do
        result = described_class.fetch_historical_data(seg, sid, interval)
        expect(result).to eq(mock_data)
      end
    end

    context "when first three methods fail, fourth succeeds" do
      let(:mock_data) do
        [{ timestamp: Time.now.to_i, open: 100.0, high: 105.0, low: 98.0, close: 103.0, volume: 1000 }]
      end

      before do
        allow(DhanHQ::Models::HistoricalData).to receive(:intraday).and_raise(StandardError, "Failed")
        allow(DhanHQ::HistoricalData).to receive(:intraday).and_raise(StandardError, "Failed")
        allow(DhanHQ::Models::HistoricalData).to receive(:fetch).and_raise(StandardError, "Failed")
        allow(DhanHQ::HistoricalData).to receive(:fetch).and_return(mock_data)
      end

      it "falls back to fourth method" do
        result = described_class.fetch_historical_data(seg, sid, interval)
        expect(result).to eq(mock_data)
      end
    end

    context "when first four methods fail, fifth succeeds" do
      let(:mock_data) do
        [{ timestamp: Time.now.to_i, open: 100.0, high: 105.0, low: 98.0, close: 103.0, volume: 1000 }]
      end

      before do
        allow(DhanHQ::Models::HistoricalData).to receive(:intraday).and_raise(StandardError, "Failed")
        allow(DhanHQ::HistoricalData).to receive(:intraday).and_raise(StandardError, "Failed")
        allow(DhanHQ::Models::HistoricalData).to receive(:fetch).and_raise(StandardError, "Failed")
        allow(DhanHQ::HistoricalData).to receive(:fetch).and_raise(StandardError, "Failed")
        allow(DhanHQ::Models::Candles).to receive(:intraday).and_return(mock_data)
      end

      it "falls back to fifth method" do
        result = described_class.fetch_historical_data(seg, sid, interval)
        expect(result).to eq(mock_data)
      end
    end

    context "when first five methods fail, sixth succeeds" do
      let(:mock_data) do
        [{ timestamp: Time.now.to_i, open: 100.0, high: 105.0, low: 98.0, close: 103.0, volume: 1000 }]
      end

      before do
        allow(DhanHQ::Models::HistoricalData).to receive(:intraday).and_raise(StandardError, "Failed")
        allow(DhanHQ::HistoricalData).to receive(:intraday).and_raise(StandardError, "Failed")
        allow(DhanHQ::Models::HistoricalData).to receive(:fetch).and_raise(StandardError, "Failed")
        allow(DhanHQ::HistoricalData).to receive(:fetch).and_raise(StandardError, "Failed")
        allow(DhanHQ::Models::Candles).to receive(:intraday).and_raise(StandardError, "Failed")
        allow(DhanHQ::Candles).to receive(:intraday).and_return(mock_data)
      end

      it "falls back to sixth method" do
        result = described_class.fetch_historical_data(seg, sid, interval)
        expect(result).to eq(mock_data)
      end
    end

    context "when all methods fail" do
      before do
        allow(DhanHQ::Models::HistoricalData).to receive(:intraday).and_raise(StandardError, "Failed")
        allow(DhanHQ::HistoricalData).to receive(:intraday).and_raise(StandardError, "Failed")
        allow(DhanHQ::Models::HistoricalData).to receive(:fetch).and_raise(StandardError, "Failed")
        allow(DhanHQ::HistoricalData).to receive(:fetch).and_raise(StandardError, "Failed")
        allow(DhanHQ::Models::Candles).to receive(:intraday).and_raise(StandardError, "Failed")
        allow(DhanHQ::Candles).to receive(:intraday).and_raise(StandardError, "Failed")
      end

      it "returns empty array" do
        result = described_class.fetch_historical_data(seg, sid, interval)
        expect(result).to eq([])
      end
    end

    context "when method returns nil" do
      before do
        allow(DhanHQ::Models::HistoricalData).to receive(:intraday).and_return(nil)
      end

      it "tries next method" do
        allow(DhanHQ::HistoricalData).to receive(:intraday).and_return([{ timestamp: Time.now.to_i, open: 100.0,
                                                                          high: 105.0, low: 98.0, close: 103.0, volume: 1000 }])
        result = described_class.fetch_historical_data(seg, sid, interval)
        expect(result).not_to be_nil
      end
    end

    context "when method returns non-array/non-hash" do
      before do
        allow(DhanHQ::Models::HistoricalData).to receive(:intraday).and_return("invalid_data")
      end

      it "tries next method" do
        allow(DhanHQ::HistoricalData).to receive(:intraday).and_return([{ timestamp: Time.now.to_i, open: 100.0,
                                                                          high: 105.0, low: 98.0, close: 103.0, volume: 1000 }])
        result = described_class.fetch_historical_data(seg, sid, interval)
        expect(result).not_to eq("invalid_data")
      end
    end
  end

  describe "#load_from_raw" do
    let(:mock_candle) { double("Candle") }

    before do
      allow(Candle).to receive(:new).and_return(mock_candle)
    end

    context "with array response" do
      let(:raw_data) do
        [
          { timestamp: Time.now.to_i, open: 100.0, high: 105.0, low: 98.0, close: 103.0, volume: 1000 },
          { timestamp: Time.now.to_i, open: 103.0, high: 107.0, low: 102.0, close: 106.0, volume: 1200 }
        ]
      end

      it "creates candles from array data" do
        series.load_from_raw(raw_data)
        expect(Candle).to have_received(:new).twice
      end

      it "adds candles to series" do
        series.load_from_raw(raw_data)
        expect(series.candles.length).to eq(2)
      end
    end

    context "with columnar hash response" do
      let(:raw_data) do
        {
          "timestamp" => [Time.now.to_i, Time.now.to_i],
          "open" => [100.0, 103.0],
          "high" => [105.0, 107.0],
          "low" => [98.0, 102.0],
          "close" => [103.0, 106.0],
          "volume" => [1000, 1200]
        }
      end

      it "creates candles from columnar data" do
        series.load_from_raw(raw_data)
        expect(Candle).to have_received(:new).twice
      end

      it "adds candles to series" do
        series.load_from_raw(raw_data)
        expect(series.candles.length).to eq(2)
      end
    end

    context "with nil response" do
      it "handles nil gracefully" do
        expect { series.load_from_raw(nil) }.not_to raise_error
        expect(series.candles).to be_empty
      end
    end

    context "with empty response" do
      it "handles empty array gracefully" do
        expect { series.load_from_raw([]) }.not_to raise_error
        expect(series.candles).to be_empty
      end

      it "handles empty hash gracefully" do
        expect { series.load_from_raw({}) }.not_to raise_error
        expect(series.candles).to be_empty
      end
    end

    context "with unexpected format" do
      it "raises error for unexpected format" do
        expect { series.load_from_raw("invalid") }.to raise_error("Unexpected candle format: String")
      end
    end
  end

  describe "#normalise_candles" do
    context "with array response" do
      let(:raw_data) do
        [
          { timestamp: Time.now.to_i, open: 100.0, high: 105.0, low: 98.0, close: 103.0, volume: 1000 }
        ]
      end

      it "calls slice_candle for each array element" do
        expect(series).to receive(:slice_candle).with(raw_data.first).and_return({})
        series.send(:normalise_candles, raw_data)
      end
    end

    context "with columnar hash response" do
      let(:raw_data) do
        {
          "timestamp" => [Time.now.to_i],
          "open" => [100.0],
          "high" => [105.0],
          "low" => [98.0],
          "close" => [103.0],
          "volume" => [1000]
        }
      end

      it "converts columnar data to row format" do
        result = series.send(:normalise_candles, raw_data)
        expect(result).to be_an(Array)
        expect(result.first).to include(:open, :high, :low, :close, :timestamp, :volume)
      end
    end
  end

  describe "#slice_candle" do
    context "with hash format" do
      let(:candle_hash) do
        {
          timestamp: Time.now.to_i,
          open: 100.0,
          high: 105.0,
          low: 98.0,
          close: 103.0,
          volume: 1000
        }
      end

      it "extracts values from hash" do
        result = series.send(:slice_candle, candle_hash)
        expect(result[:open]).to eq(100.0)
        expect(result[:high]).to eq(105.0)
        expect(result[:low]).to eq(98.0)
        expect(result[:close]).to eq(103.0)
        expect(result[:volume]).to eq(1000)
      end

      it "handles string keys" do
        candle_with_strings = {
          "timestamp" => Time.now.to_i,
          "open" => "100.0",
          "high" => "105.0",
          "low" => "98.0",
          "close" => "103.0",
          "volume" => "1000"
        }
        result = series.send(:slice_candle, candle_with_strings)
        expect(result[:open]).to eq("100.0")
      end
    end

    context "with array format" do
      let(:candle_array) { [Time.now.to_i, 100.0, 105.0, 98.0, 103.0, 1000] }

      it "extracts values from array" do
        result = series.send(:slice_candle, candle_array)
        expect(result[:timestamp]).to eq(Time.now.to_i)
        expect(result[:open]).to eq(100.0)
        expect(result[:high]).to eq(105.0)
        expect(result[:low]).to eq(98.0)
        expect(result[:close]).to eq(103.0)
        expect(result[:volume]).to eq(1000)
      end

      it "handles array without volume" do
        candle_array_no_volume = [Time.now.to_i, 100.0, 105.0, 98.0, 103.0]
        result = series.send(:slice_candle, candle_array_no_volume)
        expect(result[:volume]).to eq(0)
      end
    end

    context "with invalid format" do
      it "raises error for invalid format" do
        expect { series.send(:slice_candle, "invalid") }.to raise_error("Unexpected candle format: String")
      end

      it "raises error for array with insufficient elements" do
        expect { series.send(:slice_candle, [1, 2, 3, 4]) }.to raise_error("Unexpected candle format: [1, 2, 3, 4]")
      end
    end
  end

  describe "accessor methods" do
    let(:candles) do
      [
        double("Candle", open: 100.0, high: 105.0, low: 98.0, close: 103.0, volume: 1000),
        double("Candle", open: 103.0, high: 107.0, low: 102.0, close: 106.0, volume: 1200)
      ]
    end

    before do
      series.instance_variable_set(:@candles, candles)
    end

    describe "#opens" do
      it "returns array of open prices" do
        expect(series.opens).to eq([100.0, 103.0])
      end
    end

    describe "#closes" do
      it "returns array of close prices" do
        expect(series.closes).to eq([103.0, 106.0])
      end
    end

    describe "#highs" do
      it "returns array of high prices" do
        expect(series.highs).to eq([105.0, 107.0])
      end
    end

    describe "#lows" do
      it "returns array of low prices" do
        expect(series.lows).to eq([98.0, 102.0])
      end
    end

    describe "#volumes" do
      it "returns array of volumes" do
        expect(series.volumes).to eq([1000, 1200])
      end
    end
  end

  describe "#to_hash" do
    let(:candles) do
      [
        double("Candle", timestamp: Time.at(1000), open: 100.0, high: 105.0, low: 98.0, close: 103.0, volume: 1000),
        double("Candle", timestamp: Time.at(2000), open: 103.0, high: 107.0, low: 102.0, close: 106.0, volume: 1200)
      ]
    end

    before do
      series.instance_variable_set(:@candles, candles)
    end

    it "returns hash with all candle data" do
      result = series.to_hash
      expect(result).to include("timestamp", "open", "high", "low", "close", "volume")
      expect(result["timestamp"]).to eq([1000, 2000])
      expect(result["open"]).to eq([100.0, 103.0])
      expect(result["high"]).to eq([105.0, 107.0])
      expect(result["low"]).to eq([98.0, 102.0])
      expect(result["close"]).to eq([103.0, 106.0])
      expect(result["volume"]).to eq([1000, 1200])
    end
  end

  describe "#hlc" do
    let(:candles) do
      [
        double("Candle", timestamp: Time.at(1000), high: 105.0, low: 98.0, close: 103.0),
        double("Candle", timestamp: Time.at(2000), high: 107.0, low: 102.0, close: 106.0)
      ]
    end

    before do
      series.instance_variable_set(:@candles, candles)
    end

    it "returns array of HLC data" do
      result = series.hlc
      expect(result).to be_an(Array)
      expect(result.first).to include(:date_time, :high, :low, :close)
      expect(result.first[:high]).to eq(105.0)
      expect(result.first[:low]).to eq(98.0)
      expect(result.first[:close]).to eq(103.0)
    end
  end

  describe "pattern helpers" do
    let(:candles) do
      [
        double("Candle", high: 100.0, low: 90.0),
        double("Candle", high: 105.0, low: 95.0),
        double("Candle", high: 110.0, low: 100.0),
        double("Candle", high: 108.0, low: 98.0),
        double("Candle", high: 112.0, low: 102.0)
      ]
    end

    before do
      series.instance_variable_set(:@candles, candles)
    end

    describe "#swing_high?" do
      it "identifies swing high correctly" do
        expect(series.swing_high?(2, 2)).to be true   # Index 2 is higher than neighbors
        expect(series.swing_high?(0, 2)).to be false  # Index 0 doesn't have enough neighbors
        expect(series.swing_high?(4, 2)).to be false  # Index 4 doesn't have enough neighbors
      end
    end

    describe "#swing_low?" do
      it "identifies swing low correctly" do
        expect(series.swing_low?(1, 2)).to be false  # Index 1 is not lower than neighbors
        expect(series.swing_low?(0, 2)).to be false  # Index 0 doesn't have enough neighbors
        expect(series.swing_low?(4, 2)).to be false  # Index 4 doesn't have enough neighbors
      end
    end

    describe "#inside_bar?" do
      it "identifies inside bar correctly" do
        expect(series.inside_bar?(1)).to be false  # Index 1 is not inside index 0
        expect(series.inside_bar?(0)).to be false  # Index 0 doesn't have previous bar
      end
    end
  end

  describe "indicator methods" do
    let(:candles) do
      [
        double("Candle", close: 100.0),
        double("Candle", close: 101.0),
        double("Candle", close: 102.0),
        double("Candle", close: 103.0),
        double("Candle", close: 104.0)
      ]
    end

    before do
      series.instance_variable_set(:@candles, candles)
    end

    describe "#ema" do
      it "delegates to IndicatorsGate" do
        expect(IndicatorsGate).to receive(:ema_series).with([100.0, 101.0, 102.0, 103.0, 104.0], 20)
        series.ema(20)
      end
    end

    describe "#sma" do
      it "calculates simple moving average" do
        result = series.sma(3)
        expect(result).to eq([100.0, 100.5, 101.0, 102.0, 103.0])
      end

      it "handles empty closes array" do
        series.instance_variable_set(:@candles, [])
        result = series.sma(3)
        expect(result).to eq([])
      end
    end

    describe "#rsi" do
      it "delegates to IndicatorsGate" do
        expect(IndicatorsGate).to receive(:rsi_series).with([100.0, 101.0, 102.0, 103.0, 104.0], 14)
        series.rsi(14)
      end
    end

    describe "#macd" do
      it "delegates to RubyTechnicalAnalysis if available" do
        stub_const("RubyTechnicalAnalysis", double)
        allow(RubyTechnicalAnalysis).to receive(:const_defined?).with(:Macd).and_return(true)
        allow(RubyTechnicalAnalysis::Macd).to receive(:new).and_return(double(call: [1.0, 2.0, 3.0]))

        result = series.macd
        expect(result).to eq([1.0, 2.0, 3.0])
      end

      it "returns empty array when RubyTechnicalAnalysis not available" do
        hide_const("RubyTechnicalAnalysis")
        result = series.macd
        expect(result).to eq([])
      end
    end

    describe "#bollinger_bands" do
      it "delegates to RubyTechnicalAnalysis if available" do
        stub_const("RubyTechnicalAnalysis", double)
        allow(RubyTechnicalAnalysis).to receive(:const_defined?).with(:BollingerBands).and_return(true)
        allow(RubyTechnicalAnalysis::BollingerBands).to receive(:new).and_return(double(call: [110.0, 90.0, 100.0]))

        result = series.bollinger_bands(period: 20)
        expect(result).to eq({ upper: 110.0, lower: 90.0, middle: 100.0 })
      end

      it "returns nil when RubyTechnicalAnalysis not available" do
        hide_const("RubyTechnicalAnalysis")
        result = series.bollinger_bands(period: 20)
        expect(result).to be_nil
      end

      it "returns nil when insufficient data" do
        series.instance_variable_set(:@candles, [double("Candle", close: 100.0)])
        result = series.bollinger_bands(period: 20)
        expect(result).to be_nil
      end
    end

    describe "#donchian_channel" do
      it "delegates to IndicatorsGate" do
        expect(IndicatorsGate).to receive(:donchian).with(anything, period: 20)
        series.donchian_channel(period: 20)
      end
    end

    describe "#atr" do
      it "delegates to IndicatorsGate" do
        expect(IndicatorsGate).to receive(:atr).with(anything, period: 14)
        series.atr(14)
      end
    end

    describe "#rate_of_change" do
      it "calculates rate of change correctly" do
        result = series.rate_of_change(2)
        expect(result).to eq([nil, nil, 2.0, 1.98, 1.96])
      end

      it "handles insufficient data" do
        result = series.rate_of_change(10)
        expect(result).to eq([nil, nil, nil, nil, nil])
      end

      it "handles zero values" do
        zero_candles = [double("Candle", close: 0.0), double("Candle", close: 100.0)]
        series.instance_variable_set(:@candles, zero_candles)
        result = series.rate_of_change(1)
        expect(result).to eq([nil, nil])
      end
    end

    describe "#supertrend_signal" do
      it "delegates to IndicatorsGate" do
        allow(IndicatorsGate).to receive(:supertrend_series).and_return([100.0, 101.0, 102.0, 103.0, 104.0])

        result = series.supertrend_signal
        expect(result).to eq(:long_entry)
      end

      it "returns nil when supertrend data unavailable" do
        allow(IndicatorsGate).to receive(:supertrend_series).and_return(nil)
        result = series.supertrend_signal
        expect(result).to be_nil
      end

      it "returns nil when supertrend data is empty" do
        allow(IndicatorsGate).to receive(:supertrend_series).and_return([])
        result = series.supertrend_signal
        expect(result).to be_nil
      end

      it "identifies long entry signal" do
        allow(IndicatorsGate).to receive(:supertrend_series).and_return([100.0, 101.0, 102.0, 103.0, 104.0])
        result = series.supertrend_signal
        expect(result).to eq(:long_entry)
      end

      it "identifies short entry signal" do
        allow(IndicatorsGate).to receive(:supertrend_series).and_return([100.0, 101.0, 102.0, 103.0, 104.0])
        series.instance_variable_set(:@candles, [double("Candle", close: 95.0)])
        result = series.supertrend_signal
        expect(result).to eq(:short_entry)
      end
    end
  end
end
