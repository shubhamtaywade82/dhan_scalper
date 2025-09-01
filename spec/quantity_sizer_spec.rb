# frozen_string_literal: true

require "spec_helper"

RSpec.describe DhanScalper::QuantitySizer do
  let(:mock_balance_provider) do
    double("BalanceProvider", available_balance: 100_000.0)
  end

  let(:config) do
    {
      "global" => {
        "allocation_pct" => 0.30,
        "slippage_buffer_pct" => 0.01,
        "max_lots_per_trade" => 10
      },
      "SYMBOLS" => {
        "NIFTY" => {
          "lot_size" => 75,
          "qty_multiplier" => 5
        }
      }
    }
  end

  let(:quantity_sizer) { described_class.new(config, mock_balance_provider) }

  describe "#calculate_lots" do
    it "calculates lots based on allocation and premium" do
      lots = quantity_sizer.calculate_lots("NIFTY", 100.0)
      # 100000 * 0.30 / (100 * 1.01 * 75) = 30000 / 7575 = 3.96 -> 3 lots
      expect(lots).to eq(3)
    end

    it "respects max_lots_per_trade constraint" do
      config["global"]["max_lots_per_trade"] = 2
      lots = quantity_sizer.calculate_lots("NIFTY", 50.0)
      expect(lots).to eq(2)
    end

    it "respects qty_multiplier constraint" do
      config["SYMBOLS"]["NIFTY"]["qty_multiplier"] = 1
      lots = quantity_sizer.calculate_lots("NIFTY", 10.0)
      expect(lots).to be <= 1
    end

    it "returns 0 for negative premium" do
      lots = quantity_sizer.calculate_lots("NIFTY", -10.0)
      expect(lots).to eq(0)
    end

    it "returns 0 for zero premium" do
      lots = quantity_sizer.calculate_lots("NIFTY", 0.0)
      expect(lots).to eq(0)
    end
  end

  describe "#calculate_quantity" do
    it "calculates quantity from lots and lot size" do
      quantity = quantity_sizer.calculate_quantity("NIFTY", 100.0)
      # 3 lots * 75 = 225
      expect(quantity).to eq(225)
    end
  end

  describe "#can_afford_position?" do
    it "returns true when position is affordable" do
      result = quantity_sizer.can_afford_position?("NIFTY", 100.0)
      expect(result).to be true
    end

    it "returns false when position is not affordable" do
      result = quantity_sizer.can_afford_position?("NIFTY", 100_000.0)
      expect(result).to be false
    end
  end
end
