# frozen_string_literal: true

require "spec_helper"

RSpec.describe DhanScalper::Order do
  let(:order_id) { "ORD123" }
  let(:security_id) { "SEC456" }
  let(:side) { "BUY" }
  let(:quantity) { 100 }
  let(:price) { 150.50 }

  describe "#initialize" do
    it "creates an order with all attributes" do
      order = DhanScalper::Order.new(order_id, security_id, side, quantity, price)

      expect(order.id).to eq(order_id)
      expect(order.security_id).to eq(security_id)
      expect(order.side).to eq("BUY")
      expect(order.quantity).to eq(100)
      expect(order.price).to eq(150.50)
      expect(order.timestamp).to be_a(Time)
    end

    it "normalizes side to uppercase" do
      order = DhanScalper::Order.new(order_id, security_id, "buy", quantity, price)
      expect(order.side).to eq("BUY")
    end

    it "converts quantity to integer" do
      order = DhanScalper::Order.new(order_id, security_id, side, "100", price)
      expect(order.quantity).to eq(100)
    end

    it "converts price to float" do
      order = DhanScalper::Order.new(order_id, security_id, side, quantity, "150.50")
      expect(order.price).to eq(150.50)
    end

    it "sets timestamp to current time" do
      before_time = Time.now
      order = DhanScalper::Order.new(order_id, security_id, side, quantity, price)
      after_time = Time.now

      expect(order.timestamp).to be_between(before_time, after_time)
    end
  end

  describe "#buy?" do
    it "returns true for BUY orders" do
      order = DhanScalper::Order.new(order_id, security_id, "BUY", quantity, price)
      expect(order.buy?).to be true
    end

    it "returns false for SELL orders" do
      order = DhanScalper::Order.new(order_id, security_id, "SELL", quantity, price)
      expect(order.buy?).to be false
    end

    it "returns true for lowercase buy" do
      order = DhanScalper::Order.new(order_id, security_id, "buy", quantity, price)
      expect(order.buy?).to be true
    end
  end

  describe "#sell?" do
    it "returns true for SELL orders" do
      order = DhanScalper::Order.new(order_id, security_id, "SELL", quantity, price)
      expect(order.sell?).to be true
    end

    it "returns false for BUY orders" do
      order = DhanScalper::Order.new(order_id, security_id, "BUY", quantity, price)
      expect(order.sell?).to be false
    end

    it "returns true for lowercase sell" do
      order = DhanScalper::Order.new(order_id, security_id, "sell", quantity, price)
      expect(order.sell?).to be true
    end
  end

  describe "#total_value" do
    it "calculates total value correctly" do
      order = DhanScalper::Order.new(order_id, security_id, side, 100, 150.50)
      expect(order.total_value).to eq(15050.0)
    end

    it "handles zero quantity" do
      order = DhanScalper::Order.new(order_id, security_id, side, 0, 150.50)
      expect(order.total_value).to eq(0.0)
    end

    it "handles zero price" do
      order = DhanScalper::Order.new(order_id, security_id, side, 100, 0.0)
      expect(order.total_value).to eq(0.0)
    end

    it "handles fractional quantities" do
      order = DhanScalper::Order.new(order_id, security_id, side, 50, 150.50)
      expect(order.total_value).to eq(7525.0)
    end
  end

  describe "#to_hash" do
    it "returns a hash representation of the order" do
      order = DhanScalper::Order.new(order_id, security_id, side, quantity, price)
      hash = order.to_hash

      expect(hash[:id]).to eq(order_id)
      expect(hash[:security_id]).to eq(security_id)
      expect(hash[:side]).to eq("BUY")
      expect(hash[:quantity]).to eq(100)
      expect(hash[:price]).to eq(150.50)
      expect(hash[:timestamp]).to be_a(Time)
    end
  end

  describe "#to_s" do
    it "returns a string representation of the order" do
      order = DhanScalper::Order.new(order_id, security_id, side, quantity, price)
      expect(order.to_s).to eq("BUY 100 SEC456 @ ₹150.5")
    end

    it "handles different sides" do
      sell_order = DhanScalper::Order.new(order_id, security_id, "SELL", quantity, price)
      expect(sell_order.to_s).to eq("SELL 100 SEC456 @ ₹150.5")
    end
  end

  describe "edge cases" do
    it "handles very large numbers" do
      order = DhanScalper::Order.new(order_id, security_id, side, 1_000_000, 999_999.99)
      expect(order.total_value).to eq(999_999_990_000.0)
    end

    it "handles negative price" do
      order = DhanScalper::Order.new(order_id, security_id, side, quantity, -150.50)
      expect(order.price).to eq(-150.50)
      expect(order.total_value).to eq(-15050.0)
    end

    it "handles empty string values" do
      order = DhanScalper::Order.new("", "", "", "", "")
      expect(order.id).to eq("")
      expect(order.security_id).to eq("")
      expect(order.side).to eq("")
      expect(order.quantity).to eq(0)
      expect(order.price).to eq(0.0)
    end
  end
end
