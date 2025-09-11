# frozen_string_literal: true

require "spec_helper"

RSpec.describe DhanScalper::Support::Money do
  describe ".bd" do
    it "converts string to BigDecimal" do
      expect(described_class.bd("100.50")).to be_a(BigDecimal)
      expect(described_class.bd("100.50")).to eq(BigDecimal("100.50"))
    end

    it "converts numeric to BigDecimal" do
      expect(described_class.bd(100.50)).to be_a(BigDecimal)
      expect(described_class.bd(100.50)).to eq(BigDecimal("100.50"))
    end

    it "handles nil as zero" do
      expect(described_class.bd(nil)).to eq(BigDecimal(0))
    end

    it "returns BigDecimal as is" do
      value = BigDecimal("100.50")
      expect(described_class.bd(value)).to be(value)
    end
  end

  describe ".add" do
    it "adds two monetary values" do
      result = described_class.add("100.50", "50.25")
      expect(result).to eq(BigDecimal("150.75"))
    end
  end

  describe ".format" do
    it "formats monetary value with currency symbol" do
      result = described_class.format("100.50")
      expect(result).to eq("₹100.5")
    end
  end
end
