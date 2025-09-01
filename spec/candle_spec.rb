# frozen_string_literal: true

require "spec_helper"

RSpec.describe Candle do
  let(:valid_data) do
    {
      ts: Time.now,
      open: 100.0,
      high: 105.0,
      low: 98.0,
      close: 103.0,
      volume: 1000
    }
  end

  describe "#initialize" do
    it "creates a candle with valid data" do
      candle = Candle.new(**valid_data)

      expect(candle.timestamp).to eq(valid_data[:ts])
      expect(candle.open).to eq(100.0)
      expect(candle.high).to eq(105.0)
      expect(candle.low).to eq(98.0)
      expect(candle.close).to eq(103.0)
      expect(candle.volume).to eq(1000)
    end

    it "converts string values to appropriate types" do
      candle = Candle.new(
        ts: "2023-01-01",
        open: "100.5",
        high: "105.5",
        low: "98.5",
        close: "103.5",
        volume: "1500"
      )

      expect(candle.open).to eq(100.5)
      expect(candle.high).to eq(105.5)
      expect(candle.low).to eq(98.5)
      expect(candle.close).to eq(103.5)
      expect(candle.volume).to eq(1500)
    end

    it "handles integer values" do
      candle = Candle.new(
        ts: Time.now,
        open: 100,
        high: 105,
        low: 98,
        close: 103,
        volume: 1000
      )

      expect(candle.open).to eq(100.0)
      expect(candle.high).to eq(105.0)
      expect(candle.low).to eq(98.0)
      expect(candle.close).to eq(103.0)
      expect(candle.volume).to eq(1000)
    end
  end

  describe "#bullish?" do
    it "returns true when close is greater than open" do
      candle = Candle.new(**valid_data.merge(close: 105.0, open: 100.0))
      expect(candle.bullish?).to be true
    end

    it "returns true when close equals open" do
      candle = Candle.new(**valid_data.merge(close: 100.0, open: 100.0))
      expect(candle.bullish?).to be true
    end

    it "returns false when close is less than open" do
      candle = Candle.new(**valid_data.merge(close: 95.0, open: 100.0))
      expect(candle.bullish?).to be false
    end
  end

  describe "#bearish?" do
    it "returns true when close is less than open" do
      candle = Candle.new(**valid_data.merge(close: 95.0, open: 100.0))
      expect(candle.bearish?).to be true
    end

    it "returns false when close equals open" do
      candle = Candle.new(**valid_data.merge(close: 100.0, open: 100.0))
      expect(candle.bearish?).to be false
    end

    it "returns false when close is greater than open" do
      candle = Candle.new(**valid_data.merge(close: 105.0, open: 100.0))
      expect(candle.bearish?).to be false
    end
  end

  describe "edge cases" do
    it "handles zero values" do
      candle = Candle.new(
        ts: Time.now,
        open: 0,
        high: 0,
        low: 0,
        close: 0,
        volume: 0
      )

      expect(candle.open).to eq(0.0)
      expect(candle.high).to eq(0.0)
      expect(candle.low).to eq(0.0)
      expect(candle.close).to eq(0.0)
      expect(candle.volume).to eq(0)
      expect(candle.bullish?).to be true
      expect(candle.bearish?).to be false
    end

    it "handles negative values" do
      candle = Candle.new(
        ts: Time.now,
        open: -100,
        high: -95,
        low: -105,
        close: -98,
        volume: 1000
      )

      expect(candle.open).to eq(-100.0)
      expect(candle.high).to eq(-95.0)
      expect(candle.low).to eq(-105.0)
      expect(candle.close).to eq(-98.0)
      expect(candle.volume).to eq(1000)
      expect(candle.bullish?).to be true
      expect(candle.bearish?).to be false
    end

    it "handles very large numbers" do
      large_number = 1_000_000_000_000.0
      candle = Candle.new(
        ts: Time.now,
        open: large_number,
        high: large_number + 1000,
        low: large_number - 1000,
        close: large_number + 500,
        volume: 1_000_000
      )

      expect(candle.open).to eq(large_number)
      expect(candle.high).to eq(large_number + 1000)
      expect(candle.low).to eq(large_number - 1000)
      expect(candle.close).to eq(large_number + 500)
      expect(candle.volume).to eq(1_000_000)
    end
  end
end
