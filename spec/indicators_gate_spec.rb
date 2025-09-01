# frozen_string_literal: true

require "spec_helper"

RSpec.describe IndicatorsGate do
  let(:values) { [100.0, 101.0, 102.0, 103.0, 104.0, 105.0, 106.0, 107.0, 108.0, 109.0, 110.0] }
  let(:period) { 5 }

  describe ".ema_series" do
    context "when TechnicalAnalysis is available" do
      before do
        stub_const("TechnicalAnalysis", double)
        allow(TechnicalAnalysis).to receive(:ema).and_return([100.0, 100.5, 101.0, 101.5, 102.0])
      end

      it "uses TechnicalAnalysis.ema" do
        result = described_class.ema_series(values, period)
        expect(TechnicalAnalysis).to have_received(:ema).with(data: values, period: period)
        expect(result).to eq([100.0, 100.5, 101.0, 101.5, 102.0])
      end
    end

    context "when RubyTechnicalAnalysis is available" do
      before do
        hide_const("TechnicalAnalysis")
        stub_const("RubyTechnicalAnalysis", double)
        allow(RubyTechnicalAnalysis::Indicator::Ema).to receive(:new).and_return(double(calculate: [100.0, 100.5, 101.0, 101.5, 102.0]))
      end

      it "uses RubyTechnicalAnalysis::Indicator::Ema" do
        result = described_class.ema_series(values, period)
        expect(RubyTechnicalAnalysis::Indicator::Ema).to have_received(:new).with(period: period)
        expect(result).to eq([100.0, 100.5, 101.0, 101.5, 102.0])
      end
    end

    context "when neither library is available" do
      before do
        hide_const("TechnicalAnalysis")
        hide_const("RubyTechnicalAnalysis")
      end

      it "uses fallback calculation" do
        result = described_class.ema_series(values, period)
        expect(result).to be_an(Array)
        expect(result.length).to eq(values.length)
        expect(result.first).to eq(values.first)
      end

      it "calculates EMA correctly" do
        result = described_class.ema_series(values, period)
        # First value should be the same as input
        expect(result[0]).to eq(values[0])
        # Subsequent values should be EMA calculations
        expect(result[1]).to be_a(Float)
        expect(result[2]).to be_a(Float)
      end
    end

    context "with edge cases" do
      before do
        hide_const("TechnicalAnalysis")
        hide_const("RubyTechnicalAnalysis")
      end

      it "handles empty array" do
        result = described_class.ema_series([], period)
        expect(result).to eq([])
      end

      it "handles single value" do
        result = described_class.ema_series([100.0], period)
        expect(result).to eq([100.0])
      end

      it "handles nil values" do
        result = described_class.ema_series([nil, 100.0, 101.0], period)
        expect(result).to be_an(Array)
        expect(result.length).to eq(3)
      end
    end
  end

  describe ".rsi_series" do
    let(:period) { 14 }

    context "when TechnicalAnalysis is available" do
      before do
        stub_const("TechnicalAnalysis", double)
        allow(TechnicalAnalysis).to receive(:rsi).and_return([50.0, 55.0, 60.0, 65.0, 70.0])
      end

      it "uses TechnicalAnalysis.rsi" do
        result = described_class.rsi_series(values, period)
        expect(TechnicalAnalysis).to have_received(:rsi).with(data: values, period: period)
        expect(result).to eq([50.0, 55.0, 60.0, 65.0, 70.0])
      end
    end

    context "when RubyTechnicalAnalysis is available" do
      before do
        hide_const("TechnicalAnalysis")
        stub_const("RubyTechnicalAnalysis", double)
        allow(RubyTechnicalAnalysis::Indicator::Rsi).to receive(:new).and_return(double(calculate: [50.0, 55.0, 60.0, 65.0, 70.0]))
      end

      it "uses RubyTechnicalAnalysis::Indicator::Rsi" do
        result = described_class.rsi_series(values, period)
        expect(RubyTechnicalAnalysis::Indicator::Rsi).to have_received(:new).with(period: period)
        expect(result).to eq([50.0, 55.0, 60.0, 65.0, 70.0])
      end
    end

    context "when neither library is available" do
      before do
        hide_const("TechnicalAnalysis")
        hide_const("RubyTechnicalAnalysis")
      end

      it "uses fallback calculation" do
        result = described_class.rsi_series(values, period)
        expect(result).to be_an(Array)
        expect(result.length).to eq(values.length)
      end

      it "pads initial values with 50.0" do
        result = described_class.rsi_series(values, period)
        expect(result[0]).to eq(50.0)
        expect(result[1]).to eq(50.0)
        expect(result[period - 1]).to eq(50.0)
      end

      it "calculates RSI for subsequent values" do
        result = described_class.rsi_series(values, period)
        expect(result[period]).to be_a(Float)
        expect(result[period + 1]).to be_a(Float)
      end

      it "handles zero average loss" do
        # Create values where there are no losses
        increasing_values = (1..20).map(&:to_f)
        result = described_class.rsi_series(increasing_values, period)
        expect(result[period]).to eq(100.0)
      end
    end

    context "with edge cases" do
      before do
        hide_const("TechnicalAnalysis")
        hide_const("RubyTechnicalAnalysis")
      end

      it "handles insufficient data" do
        short_values = [100.0, 101.0, 102.0]
        result = described_class.rsi_series(short_values, period)
        expect(result).to eq([50.0, 50.0, 50.0])
      end

      it "handles single value" do
        result = described_class.rsi_series([100.0], period)
        expect(result).to eq([50.0])
      end

      it "handles empty array" do
        result = described_class.rsi_series([], period)
        expect(result).to eq([50.0])
      end
    end
  end

  describe ".supertrend_series" do
    let(:series) { double("CandleSeries") }

    context "when Indicators library is available" do
      before do
        stub_const("Indicators", double)
        allow(Indicators).to receive(:Supertrend).and_return(double(new: double(call: [100.0, 101.0, 102.0])))
      end

      it "uses Indicators::Supertrend" do
        result = described_class.supertrend_series(series)
        expect(Indicators::Supertrend).to have_received(:new).with(series: series)
        expect(result).to eq([100.0, 101.0, 102.0])
      end
    end

    context "when Indicators library is not available" do
      before do
        hide_const("Indicators")
      end

      it "returns empty array" do
        result = described_class.supertrend_series(series)
        expect(result).to eq([])
      end
    end
  end

  describe ".donchian" do
    let(:values_hlc) { [{ high: 105.0, low: 98.0, close: 103.0 }, { high: 107.0, low: 102.0, close: 106.0 }] }
    let(:period) { 20 }

    context "when TechnicalAnalysis is available" do
      before do
        stub_const("TechnicalAnalysis", double)
        allow(TechnicalAnalysis).to receive(:dc).and_return([{ upper: 107.0, lower: 98.0, middle: 102.5 }])
      end

      it "uses TechnicalAnalysis.dc" do
        result = described_class.donchian(values_hlc, period: period)
        expect(TechnicalAnalysis).to have_received(:dc).with(values_hlc, period: period)
        expect(result).to eq([{ upper: 107.0, lower: 98.0, middle: 102.5 }])
      end
    end

    context "when TechnicalAnalysis is not available" do
      before do
        hide_const("TechnicalAnalysis")
      end

      it "returns empty array" do
        result = described_class.donchian(values_hlc, period: period)
        expect(result).to eq([])
      end
    end

    context "when TechnicalAnalysis raises error" do
      before do
        stub_const("TechnicalAnalysis", double)
        allow(TechnicalAnalysis).to receive(:dc).and_raise(StandardError, "Calculation failed")
      end

      it "returns empty array" do
        result = described_class.donchian(values_hlc, period: period)
        expect(result).to eq([])
      end
    end
  end

  describe ".atr" do
    let(:values_hlc) { [{ high: 105.0, low: 98.0, close: 103.0 }, { high: 107.0, low: 102.0, close: 106.0 }] }
    let(:period) { 14 }

    context "when TechnicalAnalysis is available" do
      before do
        stub_const("TechnicalAnalysis", double)
        allow(TechnicalAnalysis).to receive(:atr).and_return([{ atr: 5.0 }, { atr: 4.5 }])
      end

      it "uses TechnicalAnalysis.atr" do
        result = described_class.atr(values_hlc, period: period)
        expect(TechnicalAnalysis).to have_received(:atr).with(values_hlc, period: period)
        expect(result).to eq([{ atr: 5.0 }, { atr: 4.5 }])
      end
    end

    context "when TechnicalAnalysis is not available" do
      before do
        hide_const("TechnicalAnalysis")
      end

      it "returns empty array" do
        result = described_class.atr(values_hlc, period: period)
        expect(result).to eq([])
      end
    end

    context "when TechnicalAnalysis raises error" do
      before do
        stub_const("TechnicalAnalysis", double)
        allow(TechnicalAnalysis).to receive(:atr).and_raise(StandardError, "Calculation failed")
      end

      it "returns empty array" do
        result = described_class.atr(values_hlc, period: period)
        expect(result).to eq([])
      end
    end
  end

  describe "fallback calculations" do
    before do
      hide_const("TechnicalAnalysis")
      hide_const("RubyTechnicalAnalysis")
      hide_const("Indicators")
    end

    describe "EMA fallback" do
      it "calculates EMA with correct formula" do
        result = described_class.ema_series([100.0, 101.0, 102.0], 2)
        expect(result).to be_an(Array)
        expect(result.length).to eq(3)

        # First value should be the same
        expect(result[0]).to eq(100.0)

        # Second value should be EMA calculation
        # k = 2/(2+1) = 0.6667
        # EMA = 101.0 * 0.6667 + 100.0 * 0.3333 = 100.67
        expect(result[1]).to be_within(0.01).of(100.67)
      end

      it "handles different periods" do
        result = described_class.ema_series([100.0, 101.0, 102.0], 5)
        expect(result).to be_an(Array)
        expect(result.length).to eq(3)

        # k = 2/(5+1) = 0.3333
        # EMA = 101.0 * 0.3333 + 100.0 * 0.6667 = 100.33
        expect(result[1]).to be_within(0.01).of(100.33)
      end
    end

    describe "RSI fallback" do
      it "calculates RSI with correct formula" do
        # Create values with clear gains and losses
        values_with_changes = [100.0, 105.0, 98.0, 103.0, 96.0, 101.0]
        result = described_class.rsi_series(values_with_changes, 3)

        expect(result).to be_an(Array)
        expect(result.length).to eq(6)

        # First 3 values should be 50.0 (padding)
        expect(result[0]).to eq(50.0)
        expect(result[1]).to eq(50.0)
        expect(result[2]).to eq(50.0)

        # Subsequent values should be calculated RSI
        expect(result[3]).to be_a(Float)
        expect(result[4]).to be_a(Float)
        expect(result[5]).to be_a(Float)
      end

      it "handles all gains" do
        increasing_values = [100.0, 101.0, 102.0, 103.0, 104.0]
        result = described_class.rsi_series(increasing_values, 3)

        # All gains should result in RSI = 100
        expect(result[3]).to eq(100.0)
        expect(result[4]).to eq(100.0)
      end

      it "handles all losses" do
        decreasing_values = [100.0, 99.0, 98.0, 97.0, 96.0]
        result = described_class.rsi_series(decreasing_values, 3)

        # All losses should result in RSI = 0
        expect(result[3]).to eq(0.0)
        expect(result[4]).to eq(0.0)
      end
    end
  end

  describe "error handling" do
    before do
      hide_const("TechnicalAnalysis")
      hide_const("RubyTechnicalAnalysis")
      hide_const("Indicators")
    end

    it "handles nil values in EMA calculation" do
      result = described_class.ema_series([nil, 100.0, 101.0], 2)
      expect(result).to be_an(Array)
      expect(result.length).to eq(3)
    end

    it "handles string values in EMA calculation" do
      result = described_class.ema_series(["100", "101", "102"], 2)
      expect(result).to be_an(Array)
      expect(result.length).to eq(3)
    end

    it "handles mixed data types in RSI calculation" do
      result = described_class.rsi_series([100.0, "101", nil, 103.0], 2)
      expect(result).to be_an(Array)
      expect(result.length).to eq(4)
    end
  end

  describe "performance characteristics" do
    before do
      hide_const("TechnicalAnalysis")
      hide_const("RubyTechnicalAnalysis")
    end

    it "handles large datasets efficiently" do
      large_values = (1..1000).map(&:to_f)
      start_time = Time.now
      result = described_class.ema_series(large_values, 20)
      end_time = Time.now

      expect(result).to be_an(Array)
      expect(result.length).to eq(1000)
      expect(end_time - start_time).to be < 1.0 # Should complete within 1 second
    end

    it "handles very small periods" do
      result = described_class.ema_series(values, 1)
      expect(result).to be_an(Array)
      expect(result.length).to eq(values.length)
    end

    it "handles very large periods" do
      result = described_class.ema_series(values, 100)
      expect(result).to be_an(Array)
      expect(result.length).to eq(values.length)
    end
  end

  describe "mathematical accuracy" do
    before do
      hide_const("TechnicalAnalysis")
      hide_const("RubyTechnicalAnalysis")
    end

    it "calculates EMA with sufficient precision" do
      # Test with known values
      test_values = [100.0, 101.0, 102.0, 103.0, 104.0]
      result = described_class.ema_series(test_values, 3)

      # k = 2/(3+1) = 0.5
      # EMA1 = 100.0
      # EMA2 = 101.0 * 0.5 + 100.0 * 0.5 = 100.5
      # EMA3 = 102.0 * 0.5 + 100.5 * 0.5 = 101.25
      # EMA4 = 103.0 * 0.5 + 101.25 * 0.5 = 102.125
      # EMA5 = 104.0 * 0.5 + 102.125 * 0.5 = 103.0625

      expect(result[0]).to eq(100.0)
      expect(result[1]).to be_within(0.001).of(100.5)
      expect(result[2]).to be_within(0.001).of(101.25)
      expect(result[3]).to be_within(0.001).of(102.125)
      expect(result[4]).to be_within(0.001).of(103.0625)
    end

    it "calculates RSI with sufficient precision" do
      # Test with known values
      test_values = [100.0, 105.0, 98.0, 103.0, 96.0, 101.0]
      result = described_class.rsi_series(test_values, 3)

      # First 3 values should be 50.0
      expect(result[0]).to eq(50.0)
      expect(result[1]).to eq(50.0)
      expect(result[2]).to eq(50.0)

      # Calculate expected RSI for index 3
      # Changes: +5, -7, +5, -7, +5
      # Gains: 5, 5, 5 (avg = 5)
      # Losses: 7, 7 (avg = 7)
      # RS = 5/7 = 0.714
      # RSI = 100 - (100/(1+0.714)) = 41.67
      expect(result[3]).to be_within(0.1).of(41.67)
    end
  end
end
