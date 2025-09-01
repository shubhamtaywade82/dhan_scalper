require "spec_helper"

RSpec.describe DhanScalper::Order do
  let(:order) { described_class.new(1, "ABC", "buy", 10, 100) }

  it "identifies buy and sell" do
    expect(order.buy?).to be true
    expect(order.sell?).to be false
  end

  it "calculates total value" do
    expect(order.total_value).to eq(1000.0)
  end

  it "returns hash representation" do
    expect(order.to_hash).to include(id: 1, security_id: "ABC", quantity: 10)
  end

  it "stringifies order" do
    expect(order.to_s).to include("BUY 10 ABC @ ₹100.0")
  end
end
