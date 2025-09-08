# frozen_string_literal: true

require "spec_helper"

RSpec.describe DhanScalper::ExchangeSegmentMapper do
  describe ".exchange_segment" do
    context "with valid exchange and segment combinations" do
      it "maps NSE index to IDX_I" do
        expect(described_class.exchange_segment("NSE", "I")).to eq("IDX_I")
        expect(described_class.exchange_segment(:nse, :i)).to eq("IDX_I")
      end

      it "maps BSE index to IDX_I" do
        expect(described_class.exchange_segment("BSE", "I")).to eq("IDX_I")
        expect(described_class.exchange_segment(:bse, :i)).to eq("IDX_I")
      end

      it "maps NSE equity to NSE_EQ" do
        expect(described_class.exchange_segment("NSE", "E")).to eq("NSE_EQ")
        expect(described_class.exchange_segment(:nse, :e)).to eq("NSE_EQ")
      end

      it "maps BSE equity to BSE_EQ" do
        expect(described_class.exchange_segment("BSE", "E")).to eq("BSE_EQ")
        expect(described_class.exchange_segment(:bse, :e)).to eq("BSE_EQ")
      end

      it "maps NSE derivatives to NSE_FNO" do
        expect(described_class.exchange_segment("NSE", "D")).to eq("NSE_FNO")
        expect(described_class.exchange_segment(:nse, :d)).to eq("NSE_FNO")
      end

      it "maps BSE derivatives to BSE_FNO" do
        expect(described_class.exchange_segment("BSE", "D")).to eq("BSE_FNO")
        expect(described_class.exchange_segment(:bse, :d)).to eq("BSE_FNO")
      end

      it "maps NSE currency to NSE_CURRENCY" do
        expect(described_class.exchange_segment("NSE", "C")).to eq("NSE_CURRENCY")
        expect(described_class.exchange_segment(:nse, :c)).to eq("NSE_CURRENCY")
      end

      it "maps BSE currency to BSE_CURRENCY" do
        expect(described_class.exchange_segment("BSE", "C")).to eq("BSE_CURRENCY")
        expect(described_class.exchange_segment(:bse, :c)).to eq("BSE_CURRENCY")
      end

      it "maps MCX commodity to MCX_COMM" do
        expect(described_class.exchange_segment("MCX", "M")).to eq("MCX_COMM")
        expect(described_class.exchange_segment(:mcx, :m)).to eq("MCX_COMM")
      end

      it "is case insensitive" do
        expect(described_class.exchange_segment("nse", "e")).to eq("NSE_EQ")
        expect(described_class.exchange_segment("Bse", "D")).to eq("BSE_FNO")
        expect(described_class.exchange_segment("mCx", "M")).to eq("MCX_COMM")
      end
    end

    context "with invalid exchange and segment combinations" do
      it "raises ArgumentError for unsupported combinations" do
        expect do
          described_class.exchange_segment("NSE",
                                           "X")
        end.to raise_error(ArgumentError, /Unsupported exchange and segment combination/)
        expect do
          described_class.exchange_segment("INVALID",
                                           "E")
        end.to raise_error(ArgumentError, /Unsupported exchange and segment combination/)
        expect do
          described_class.exchange_segment("MCX",
                                           "E")
        end.to raise_error(ArgumentError, /Unsupported exchange and segment combination/)
      end
    end
  end

  describe ".segment_name" do
    it "maps segment codes to human-readable names" do
      expect(described_class.segment_name("I")).to eq("Index")
      expect(described_class.segment_name("E")).to eq("Equity")
      expect(described_class.segment_name("D")).to eq("Derivatives")
      expect(described_class.segment_name("C")).to eq("Currency")
      expect(described_class.segment_name("M")).to eq("Commodity")
    end

    it "handles symbols and is case insensitive" do
      expect(described_class.segment_name(:i)).to eq("Index")
      expect(described_class.segment_name("e")).to eq("Equity")
      expect(described_class.segment_name("D")).to eq("Derivatives")
    end

    it "returns unknown for invalid segments" do
      expect(described_class.segment_name("X")).to eq("Unknown (X)")
      expect(described_class.segment_name("INVALID")).to eq("Unknown (INVALID)")
    end
  end

  describe ".exchange_name" do
    it "maps exchange codes to human-readable names" do
      expect(described_class.exchange_name("NSE")).to eq("National Stock Exchange")
      expect(described_class.exchange_name("BSE")).to eq("Bombay Stock Exchange")
      expect(described_class.exchange_name("MCX")).to eq("Multi Commodity Exchange")
    end

    it "handles symbols and is case insensitive" do
      expect(described_class.exchange_name(:nse)).to eq("National Stock Exchange")
      expect(described_class.exchange_name("bse")).to eq("Bombay Stock Exchange")
      expect(described_class.exchange_name("McX")).to eq("Multi Commodity Exchange")
    end

    it "returns unknown for invalid exchanges" do
      expect(described_class.exchange_name("INVALID")).to eq("Unknown (INVALID)")
      expect(described_class.exchange_name("X")).to eq("Unknown (X)")
    end
  end

  describe ".supported_combinations" do
    it "returns all supported exchange-segment combinations" do
      combinations = described_class.supported_combinations
      expect(combinations).to include(%w[NSE I], %w[BSE I])
      expect(combinations).to include(%w[NSE E], %w[BSE E])
      expect(combinations).to include(%w[NSE D], %w[BSE D])
      expect(combinations).to include(%w[NSE C], %w[BSE C])
      expect(combinations).to include(%w[MCX M])
      expect(combinations.length).to eq(9)
    end
  end

  describe ".supported?" do
    it "returns true for supported combinations" do
      expect(described_class.supported?("NSE", "E")).to be true
      expect(described_class.supported?("BSE", "I")).to be true
      expect(described_class.supported?("MCX", "M")).to be true
      expect(described_class.supported?(:nse, :d)).to be true
    end

    it "returns false for unsupported combinations" do
      expect(described_class.supported?("NSE", "X")).to be false
      expect(described_class.supported?("INVALID", "E")).to be false
      expect(described_class.supported?("MCX", "E")).to be false
    end

    it "is case insensitive" do
      expect(described_class.supported?("nse", "e")).to be true
      expect(described_class.supported?("BSE", "i")).to be true
    end
  end
end
