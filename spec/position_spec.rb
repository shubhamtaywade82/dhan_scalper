# frozen_string_literal: true

require "spec_helper"

RSpec.describe DhanScalper::Position do
  let(:security_id) { "SEC123" }
  let(:side) { "BUY" }
  let(:entry_price) { 150.0 }
  let(:quantity) { 100 }
  let(:symbol) { "NIFTY" }

  describe "#initialize" do
    it "creates a position with all attributes" do
      position = described_class.new(
        security_id: security_id,
        side: side,
        entry_price: entry_price,
        quantity: quantity,
        symbol: symbol,
      )

      expect(position.symbol).to eq(symbol)
      expect(position.security_id).to eq(security_id)
      expect(position.side).to eq(side)
      expect(position.entry_price).to eq(entry_price)
      expect(position.quantity).to eq(quantity)
      expect(position.current_price).to eq(entry_price)
      expect(position.pnl).to eq(0.0)
    end

    it "sets current_price to entry_price by default" do
      position = described_class.new(
        security_id: security_id,
        side: side,
        entry_price: entry_price,
        quantity: quantity,
      )

      expect(position.current_price).to eq(entry_price)
    end

    it "allows custom current_price" do
      position = described_class.new(
        security_id: security_id,
        side: side,
        entry_price: entry_price,
        quantity: quantity,
        current_price: 160.0,
      )

      expect(position.current_price).to eq(160.0)
    end

    it "allows custom pnl" do
      position = described_class.new(
        security_id: security_id,
        side: side,
        entry_price: entry_price,
        quantity: quantity,
        pnl: 1_000.0,
      )

      expect(position.pnl).to eq(1_000.0)
    end
  end

  describe "#update_price" do
    let(:position) do
      described_class.new(
        security_id: security_id,
        side: side,
        entry_price: entry_price,
        quantity: quantity,
      )
    end

    it "updates current_price and recalculates pnl" do
      position.update_price(160.0)

      expect(position.current_price).to eq(160.0)
      expect(position.pnl).to eq(1_000.0) # (160 - 150) * 100
    end

    it "handles price decrease" do
      position.update_price(140.0)

      expect(position.current_price).to eq(140.0)
      expect(position.pnl).to eq(-1_000.0) # (140 - 150) * 100
    end

    it "handles zero price" do
      position.update_price(0.0)

      expect(position.current_price).to eq(0.0)
      expect(position.pnl).to eq(-15_000.0) # (0 - 150) * 100
    end
  end

  describe "#calculate_pnl" do
    context "for BUY positions" do
      let(:position) do
        described_class.new(
          security_id: security_id,
          side: "BUY",
          entry_price: 150.0,
          quantity: 100,
        )
      end

      it "calculates profit correctly" do
        position.current_price = 160.0
        expect(position.calculate_pnl).to eq(1_000.0)
      end

      it "calculates loss correctly" do
        position.current_price = 140.0
        expect(position.calculate_pnl).to eq(-1_000.0)
      end

      it "calculates breakeven correctly" do
        position.current_price = 150.0
        expect(position.calculate_pnl).to eq(0.0)
      end
    end

    context "for SELL positions" do
      let(:position) do
        described_class.new(
          security_id: security_id,
          side: "SELL",
          entry_price: 150.0,
          quantity: 100,
        )
      end

      it "calculates profit when price goes down" do
        position.current_price = 140.0
        expect(position.calculate_pnl).to eq(1_000.0) # (150 - 140) * 100
      end

      it "calculates loss when price goes up" do
        position.current_price = 160.0
        expect(position.calculate_pnl).to eq(-1_000.0) # (150 - 160) * 100
      end

      it "calculates breakeven correctly" do
        position.current_price = 150.0
        expect(position.calculate_pnl).to eq(0.0)
      end
    end

    it "handles unknown side" do
      position = described_class.new(
        security_id: security_id,
        side: "UNKNOWN",
        entry_price: 150.0,
        quantity: 100,
      )

      expect(position.calculate_pnl).to eq(0.0)
    end

    it "handles case insensitive side" do
      position = described_class.new(
        security_id: security_id,
        side: "buy",
        entry_price: 150.0,
        quantity: 100,
      )
      position.current_price = 160.0

      expect(position.calculate_pnl).to eq(1_000.0)
    end
  end

  describe "#to_h" do
    it "returns a hash representation" do
      position = described_class.new(
        security_id: security_id,
        side: side,
        entry_price: entry_price,
        quantity: quantity,
        symbol: symbol,
        current_price: 160.0,
        pnl: 1_000.0,
      )

      hash = position.to_h

      expect(hash[:symbol]).to eq(symbol)
      expect(hash[:security_id]).to eq(security_id)
      expect(hash[:side]).to eq(side)
      expect(hash[:entry_price]).to eq(entry_price)
      expect(hash[:quantity]).to eq(quantity)
      expect(hash[:current_price]).to eq(160.0)
      expect(hash[:pnl]).to eq(1_000.0)
    end
  end

  describe "#to_s" do
    it "returns a string representation" do
      position = described_class.new(
        security_id: security_id,
        side: side,
        entry_price: entry_price,
        quantity: quantity,
        symbol: symbol,
        current_price: 160.0,
        pnl: 1_000.0,
      )

      expect(position.to_s).to eq("BUY 100 NIFTY @ 150.0 (Current: 160.0, P&L: 1000.0)")
    end

    it "uses security_id when symbol is nil" do
      position = described_class.new(
        security_id: security_id,
        side: side,
        entry_price: entry_price,
        quantity: quantity,
        symbol: nil,
      )

      expect(position.to_s).to include(security_id)
    end
  end

  describe "edge cases" do
    it "handles zero quantity" do
      position = described_class.new(
        security_id: security_id,
        side: side,
        entry_price: entry_price,
        quantity: 0,
      )

      expect(position.calculate_pnl).to eq(0.0)
    end

    it "handles negative quantity" do
      position = described_class.new(
        security_id: security_id,
        side: side,
        entry_price: entry_price,
        quantity: -100,
      )

      expect(position.calculate_pnl).to eq(0.0) # Should handle gracefully
    end

    it "handles very large numbers" do
      position = described_class.new(
        security_id: security_id,
        side: side,
        entry_price: 1_000_000.0,
        quantity: 1_000_000,
      )
      position.current_price = 1_000_100.0

      expect(position.calculate_pnl).to eq(100_000_000.0)
    end

    it "handles fractional prices" do
      position = described_class.new(
        security_id: security_id,
        side: side,
        entry_price: 150.123,
        quantity: 100,
      )
      position.current_price = 150.456

      expect(position.calculate_pnl).to eq(33.3) # (150.456 - 150.123) * 100
    end
  end
end
