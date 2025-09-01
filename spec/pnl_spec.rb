require "spec_helper"

RSpec.describe DhanScalper::PnL do
  it "calculates round trip charges" do
    expect(described_class.round_trip_orders(20)).to eq(40)
  end

  it "calculates net pnl" do
    net = described_class.net(entry: 100.0, ltp: 110.0, lot_size: 75, qty_lots: 2, charge_per_order: 20)
    # (10 * 150) - 40 = 1460
    expect(net).to eq(1460.0)
  end
end
