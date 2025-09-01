require "spec_helper"

RSpec.describe DhanScalper::TickCache do
  it "stores and retrieves ltp" do
    tick = { segment: "NSE", security_id: "123", ltp: 101.5 }
    described_class.put(tick)
    expect(described_class.ltp("NSE", "123")).to eq(101.5)
  end

  it "returns nil for unknown key" do
    expect(described_class.ltp("NSE", "999")).to be_nil
  end
end
