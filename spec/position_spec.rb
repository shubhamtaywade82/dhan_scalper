require "spec_helper"

RSpec.describe DhanScalper::Position do
  let(:position) { described_class.new(security_id: "1", side: "BUY", entry_price: 100.0, quantity: 10, symbol: "ABC") }

  it "calculates pnl for buy side" do
    position.update_price(105.0)
    expect(position.pnl).to eq(50.0)
  end

  it "calculates pnl for sell side" do
    sell_pos = described_class.new(security_id: "1", side: "SELL", entry_price: 100.0, quantity: 10)
    sell_pos.update_price(90.0)
    expect(sell_pos.pnl).to eq(100.0)
  end

  it "converts to hash" do
    expect(position.to_h).to include(symbol: "ABC", security_id: "1")
  end

  it "stringifies position" do
    expect(position.to_s).to include("BUY 10 ABC @ 100.0")
  end
end
