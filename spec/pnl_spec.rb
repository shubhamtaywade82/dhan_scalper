# frozen_string_literal: true

require "spec_helper"

RSpec.describe DhanScalper::PnL do
  describe ".round_trip_orders" do
    it "calculates round trip charges correctly" do
      expect(DhanScalper::PnL.round_trip_orders(20)).to eq(40)
    end

    it "handles zero charge" do
      expect(DhanScalper::PnL.round_trip_orders(0)).to eq(0)
    end

    it "handles fractional charges" do
      expect(DhanScalper::PnL.round_trip_orders(15.5)).to eq(31.0)
    end

    it "handles large charges" do
      expect(DhanScalper::PnL.round_trip_orders(100)).to eq(200)
    end
  end

  describe ".net" do
    let(:entry) { 100.0 }
    let(:ltp) { 110.0 }
    let(:lot_size) { 75 }
    let(:qty_lots) { 2 }
    let(:charge_per_order) { 20.0 }

    it "calculates net profit correctly" do
      # Gross profit: (110 - 100) * (75 * 2) = 10 * 150 = 1500
      # Charges: 2 * 20 = 40
      # Net: 1500 - 40 = 1460
      net = DhanScalper::PnL.net(
        entry: entry,
        ltp: ltp,
        lot_size: lot_size,
        qty_lots: qty_lots,
        charge_per_order: charge_per_order
      )

      expect(net).to eq(1460.0)
    end

    it "calculates net loss correctly" do
      # Gross loss: (90 - 100) * (75 * 2) = -10 * 150 = -1500
      # Charges: 2 * 20 = 40
      # Net: -1500 - 40 = -1540
      net = DhanScalper::PnL.net(
        entry: entry,
        ltp: 90.0,
        lot_size: lot_size,
        qty_lots: qty_lots,
        charge_per_order: charge_per_order
      )

      expect(net).to eq(-1540.0)
    end

    it "calculates breakeven correctly" do
      # Gross: (100 - 100) * (75 * 2) = 0
      # Charges: 2 * 20 = 40
      # Net: 0 - 40 = -40
      net = DhanScalper::PnL.net(
        entry: entry,
        ltp: entry,
        lot_size: lot_size,
        qty_lots: qty_lots,
        charge_per_order: charge_per_order
      )

      expect(net).to eq(-40.0)
    end

    it "handles zero quantity" do
      net = DhanScalper::PnL.net(
        entry: entry,
        ltp: ltp,
        lot_size: lot_size,
        qty_lots: 0,
        charge_per_order: charge_per_order
      )

      expect(net).to eq(-40.0) # Only charges
    end

    it "handles zero lot size" do
      net = DhanScalper::PnL.net(
        entry: entry,
        ltp: ltp,
        lot_size: 0,
        qty_lots: qty_lots,
        charge_per_order: charge_per_order
      )

      expect(net).to eq(-40.0) # Only charges
    end

    it "handles zero charges" do
      net = DhanScalper::PnL.net(
        entry: entry,
        ltp: ltp,
        lot_size: lot_size,
        qty_lots: qty_lots,
        charge_per_order: 0
      )

      expect(net).to eq(1500.0) # Only gross profit
    end

    it "handles fractional prices" do
      net = DhanScalper::PnL.net(
        entry: 100.25,
        ltp: 110.75,
        lot_size: lot_size,
        qty_lots: qty_lots,
        charge_per_order: charge_per_order
      )

      # Gross: (110.75 - 100.25) * (75 * 2) = 10.5 * 150 = 1575
      # Charges: 40
      # Net: 1575 - 40 = 1535
      expect(net).to eq(1535.0)
    end

    it "handles large numbers" do
      net = DhanScalper::PnL.net(
        entry: 1_000_000.0,
        ltp: 1_000_100.0,
        lot_size: 1_000_000,
        qty_lots: 1,
        charge_per_order: 1000.0
      )

      # Gross: 100 * 1_000_000 = 100_000_000
      # Charges: 2000
      # Net: 100_000_000 - 2000 = 99_998_000
      expect(net).to eq(99_998_000.0)
    end

    it "handles negative entry price" do
      net = DhanScalper::PnL.net(
        entry: -100.0,
        ltp: -90.0,
        lot_size: lot_size,
        qty_lots: qty_lots,
        charge_per_order: charge_per_order
      )

      # Gross: (-90 - (-100)) * (75 * 2) = 10 * 150 = 1500
      # Charges: 40
      # Net: 1500 - 40 = 1460
      expect(net).to eq(1460.0)
    end

    it "handles negative LTP" do
      net = DhanScalper::PnL.net(
        entry: 100.0,
        ltp: -50.0,
        lot_size: lot_size,
        qty_lots: qty_lots,
        charge_per_order: charge_per_order
      )

      # Gross: (-50 - 100) * (75 * 2) = -150 * 150 = -22500
      # Charges: 40
      # Net: -22500 - 40 = -22540
      expect(net).to eq(-22540.0)
    end

    context "with different lot sizes and quantities" do
      it "calculates with single lot" do
        net = DhanScalper::PnL.net(
          entry: entry,
          ltp: ltp,
          lot_size: 50,
          qty_lots: 1,
          charge_per_order: charge_per_order
        )

        # Gross: 10 * 50 = 500
        # Charges: 40
        # Net: 500 - 40 = 460
        expect(net).to eq(460.0)
      end

      it "calculates with multiple lots" do
        net = DhanScalper::PnL.net(
          entry: entry,
          ltp: ltp,
          lot_size: 25,
          qty_lots: 4,
          charge_per_order: charge_per_order
        )

        # Gross: 10 * (25 * 4) = 10 * 100 = 1000
        # Charges: 40
        # Net: 1000 - 40 = 960
        expect(net).to eq(960.0)
      end
    end
  end

  describe "edge cases" do
    it "handles all zero values" do
      net = DhanScalper::PnL.net(
        entry: 0,
        ltp: 0,
        lot_size: 0,
        qty_lots: 0,
        charge_per_order: 0
      )

      expect(net).to eq(0.0)
    end

    it "handles very small fractional values" do
      net = DhanScalper::PnL.net(
        entry: 0.001,
        ltp: 0.002,
        lot_size: 1,
        qty_lots: 1,
        charge_per_order: 0.01
      )

      # Gross: 0.001 * 1 = 0.001
      # Charges: 0.02
      # Net: 0.001 - 0.02 = -0.019
      expect(net).to be_within(0.0001).of(-0.019)
    end

    it "handles extreme price differences" do
      net = DhanScalper::PnL.net(
        entry: 1.0,
        ltp: 1000.0,
        lot_size: 1,
        qty_lots: 1,
        charge_per_order: 1.0
      )

      # Gross: 999 * 1 = 999
      # Charges: 2
      # Net: 999 - 2 = 997
      expect(net).to eq(997.0)
    end
  end
end
