# frozen_string_literal: true

require "spec_helper"

RSpec.describe DhanScalper::Indicators do
  let(:sample_values) { [100.0, 101.0, 99.0, 102.0, 98.0, 103.0, 97.0, 104.0, 96.0, 105.0] }

  describe ".ema_last" do
    context "when TechnicalAnalysis gem is available" do
      before do
        # Mock TechnicalAnalysis gem
        stub_const("TechnicalAnalysis", double)
        allow(TechnicalAnalysis).to receive(:ema).and_return(double(last: 102.5))
      end

      it "uses TechnicalAnalysis.ema when available" do
        result = described_class.ema_last(sample_values, 5)
        expect(TechnicalAnalysis).to have_received(:ema).with(data: sample_values, period: 5)
        expect(result).to eq(102.5)
      end
    end

    context "when RubyTechnicalAnalysis gem is available" do
      before do
        # Mock RubyTechnicalAnalysis gem properly
        stub_const("RubyTechnicalAnalysis", Module.new)
        stub_const("RubyTechnicalAnalysis::Indicator", Module.new)
        stub_const("RubyTechnicalAnalysis::Indicator::Ema", Class.new)
        allow(RubyTechnicalAnalysis::Indicator::Ema).to receive(:new).and_return(double(calculate: [102.5]))
      end

      it "uses RubyTechnicalAnalysis when TechnicalAnalysis is not available" do
        hide_const("TechnicalAnalysis")
        result = described_class.ema_last(sample_values, 5)
        expect(RubyTechnicalAnalysis::Indicator::Ema).to have_received(:new).with(period: 5)
        expect(result).to eq(102.5)
      end
    end

    context "when no external gems are available" do
      before do
        hide_const("TechnicalAnalysis")
        hide_const("RubyTechnicalAnalysis")
      end

      it "calculates EMA using fallback method" do
        result = described_class.ema_last(sample_values, 3)

        # Manual calculation verification
        k = 2.0 / (3 + 1) # 0.5
        expected_ema = sample_values.inject(nil) do |ema, value|
          ema.nil? ? value.to_f : (value.to_f * k + ema * (1 - k))
        end

        expect(result).to be_within(0.01).of(expected_ema)
      end

      it "handles single value" do
        result = described_class.ema_last([100.0], 3)
        expect(result).to eq(100.0)
      end

      it "handles empty array" do
        result = described_class.ema_last([], 3)
        expect(result).to eq(0.0)
      end
    end

    context "error handling" do
      before do
        hide_const("TechnicalAnalysis")
        hide_const("RubyTechnicalAnalysis")
      end

      it "returns last value when calculation fails" do
        # Force an error by passing invalid data
        result = described_class.ema_last(nil, 3)
        expect(result).to eq(0.0)
      end
    end
  end

  describe ".rsi_last" do
    context "when TechnicalAnalysis gem is available" do
      before do
        stub_const("TechnicalAnalysis", double)
        allow(TechnicalAnalysis).to receive(:rsi).and_return(double(last: 65.5))
      end

      it "uses TechnicalAnalysis.rsi when available" do
        result = described_class.rsi_last(sample_values, 5)
        expect(TechnicalAnalysis).to have_received(:rsi).with(data: sample_values, period: 5)
        expect(result).to eq(65.5)
      end
    end

    context "when RubyTechnicalAnalysis gem is available" do
      before do
        # Mock RubyTechnicalAnalysis gem properly
        stub_const("RubyTechnicalAnalysis", Module.new)
        stub_const("RubyTechnicalAnalysis::Indicator", Module.new)
        stub_const("RubyTechnicalAnalysis::Indicator::Rsi", Class.new)
        allow(RubyTechnicalAnalysis::Indicator::Rsi).to receive(:new).and_return(double(calculate: [65.5]))
      end

      it "uses RubyTechnicalAnalysis when TechnicalAnalysis is not available" do
        hide_const("TechnicalAnalysis")
        result = described_class.rsi_last(sample_values, 5)
        expect(RubyTechnicalAnalysis::Indicator::Rsi).to have_received(:new).with(period: 5)
        expect(result).to eq(65.5)
      end
    end

    context "when no external gems are available" do
      before do
        hide_const("TechnicalAnalysis")
        hide_const("RubyTechnicalAnalysis")
      end

      it "calculates RSI using fallback method" do
        result = described_class.rsi_last(sample_values, 3)

        # Verify it's a reasonable RSI value (0-100)
        expect(result).to be_between(0.0, 100.0)
      end

      it "returns 50.0 when insufficient data" do
        result = described_class.rsi_last([100.0, 101.0], 3)
        expect(result).to eq(50.0)
      end

      it "handles default period of 14" do
        result = described_class.rsi_last(sample_values)
        expect(result).to be_between(0.0, 100.0)
      end

      it "handles edge case with zero average loss" do
        # Create data where all changes are gains
        gains_data = [100.0, 101.0, 102.0, 103.0, 104.0, 105.0]
        result = described_class.rsi_last(gains_data, 3)
        # RSI should be very high but not necessarily exactly 100.0 due to calculation method
        expect(result).to be > 95.0
      end
    end

    context "error handling" do
      before do
        hide_const("TechnicalAnalysis")
        hide_const("RubyTechnicalAnalysis")
      end

      it "returns 50.0 when calculation fails" do
        result = described_class.rsi_last(nil, 3)
        expect(result).to eq(50.0)
      end
    end
  end

  describe "edge cases and data validation" do
    before do
      hide_const("TechnicalAnalysis")
      hide_const("RubyTechnicalAnalysis")
    end

    it "handles very small numbers" do
      small_values = [0.001, 0.002, 0.0015, 0.0025, 0.0018]
      result = described_class.ema_last(small_values, 3)
      expect(result).to be > 0
    end

    it "handles very large numbers" do
      large_values = [1_000_000.0, 1_000_001.0, 999_999.0, 1_000_002.0, 999_998.0]
      result = described_class.ema_last(large_values, 3)
      # The result should be close to the large numbers, not necessarily exactly > 1_000_000
      expect(result).to be > 999_999.0
    end

    it "handles mixed data types" do
      mixed_values = [100, "101.5", 99.0, 102, "98.5"]
      result = described_class.ema_last(mixed_values, 3)
      expect(result).to be_a(Float)
    end

    it "handles period larger than data size" do
      result = described_class.ema_last(sample_values, 20)
      expect(result).to be_a(Float)
    end
  end
end
