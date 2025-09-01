# frozen_string_literal: true

require "spec_helper"

RSpec.describe DhanScalper::Brokers::Base do
  let(:base_class) { Class.new(described_class) }
  let(:broker) { base_class.new }

  describe "abstract methods" do
    it "raises NotImplementedError for buy" do
      expect { broker.buy("NIFTY", 100, 50.0) }.to raise_error(NotImplementedError)
    end

    it "raises NotImplementedError for sell" do
      expect { broker.sell("NIFTY", 100, 50.0) }.to raise_error(NotImplementedError)
    end

    it "raises NotImplementedError for square_off" do
      expect { broker.square_off("NIFTY", 100) }.to raise_error(NotImplementedError)
    end

    it "raises NotImplementedError for get_positions" do
      expect { broker.get_positions }.to raise_error(NotImplementedError)
    end

    it "raises NotImplementedError for get_orders" do
      expect { broker.get_orders }.to raise_error(NotImplementedError)
    end
  end

  describe "interface contract" do
    it "defines the required interface methods" do
      expect(described_class.instance_methods).to include(:buy)
      expect(described_class.instance_methods).to include(:sell)
      expect(described_class.instance_methods).to include(:square_off)
      expect(described_class.instance_methods).to include(:get_positions)
      expect(described_class.instance_methods).to include(:get_orders)
    end

    it "ensures subclasses implement required methods" do
      # Create a subclass that doesn't implement required methods
      incomplete_class = Class.new(described_class)
      incomplete_broker = incomplete_class.new

      expect { incomplete_broker.buy("NIFTY", 100, 50.0) }.to raise_error(NotImplementedError)
      expect { incomplete_broker.sell("NIFTY", 100, 50.0) }.to raise_error(NotImplementedError)
      expect { incomplete_broker.square_off("NIFTY", 100) }.to raise_error(NotImplementedError)
      expect { incomplete_broker.get_positions }.to raise_error(NotImplementedError)
      expect { incomplete_broker.get_orders }.to raise_error(NotImplementedError)
    end
  end

  describe "method signatures" do
    it "allows buy to accept symbol, quantity, and price parameters" do
      method = described_class.instance_method(:buy)
      expect(method.parameters).to include([:req, :symbol])
      expect(method.parameters).to include([:req, :quantity])
      expect(method.parameters).to include([:req, :price])
    end

    it "allows sell to accept symbol, quantity, and price parameters" do
      method = described_class.instance_method(:sell)
      expect(method.parameters).to include([:req, :symbol])
      expect(method.parameters).to include([:req, :quantity])
      expect(method.parameters).to include([:req, :price])
    end

    it "allows square_off to accept symbol and quantity parameters" do
      method = described_class.instance_method(:square_off)
      expect(method.parameters).to include([:req, :symbol])
      expect(method.parameters).to include([:req, :quantity])
    end

    it "allows get_positions to accept no parameters" do
      method = described_class.instance_method(:get_positions)
      expect(method.parameters).to be_empty
    end

    it "allows get_orders to accept no parameters" do
      method = described_class.instance_method(:get_orders)
      expect(method.parameters).to be_empty
    end
  end

  describe "inheritance" do
    it "can be inherited from" do
      expect { Class.new(described_class) }.not_to raise_error
    end

    it "maintains abstract method requirements" do
      child_class = Class.new(described_class) do
        def buy(symbol, quantity, price)
          "Buy order placed"
        end
      end

      child_broker = child_class.new

      # Should work for implemented method
      expect(child_broker.buy("NIFTY", 100, 50.0)).to eq("Buy order placed")

      # Should still raise for unimplemented methods
      expect { child_broker.sell("NIFTY", 100, 50.0) }.to raise_error(NotImplementedError)
      expect { child_broker.square_off("NIFTY", 100) }.to raise_error(NotImplementedError)
      expect { child_broker.get_positions }.to raise_error(NotImplementedError)
      expect { child_broker.get_orders }.to raise_error(NotImplementedError)
    end
  end

  describe "error messages" do
    it "provides clear error messages for NotImplementedError" do
      expect { broker.buy("NIFTY", 100, 50.0) }.to raise_error(NotImplementedError, /buy/)
      expect { broker.sell("NIFTY", 100, 50.0) }.to raise_error(NotImplementedError, /sell/)
      expect { broker.square_off("NIFTY", 100) }.to raise_error(NotImplementedError, /square_off/)
      expect { broker.get_positions }.to raise_error(NotImplementedError, /get_positions/)
      expect { broker.get_orders }.to raise_error(NotImplementedError, /get_orders/)
    end
  end

  describe "method behavior expectations" do
    it "expects buy to return order result" do
      # This test documents the expected behavior
      # The actual implementation will vary by subclass
      expect(described_class.instance_method(:buy).arity).to eq(3)
    end

    it "expects sell to return order result" do
      expect(described_class.instance_method(:sell).arity).to eq(3)
    end

    it "expects square_off to return result" do
      expect(described_class.instance_method(:square_off).arity).to eq(2)
    end

    it "expects get_positions to return array" do
      expect(described_class.instance_method(:get_positions).arity).to eq(0)
    end

    it "expects get_orders to return array" do
      expect(described_class.instance_method(:get_orders).arity).to eq(0)
    end
  end

  describe "subclass implementation example" do
    let(:implemented_class) do
      Class.new(described_class) do
        def buy(symbol, quantity, price)
          { action: "BUY", symbol: symbol, quantity: quantity, price: price, status: "SUCCESS" }
        end

        def sell(symbol, quantity, price)
          { action: "SELL", symbol: symbol, quantity: quantity, price: price, status: "SUCCESS" }
        end

        def square_off(symbol, quantity)
          { action: "SQUARE_OFF", symbol: symbol, quantity: quantity, status: "SUCCESS" }
        end

        def get_positions
          [{ symbol: "NIFTY", quantity: 100, side: "LONG" }]
        end

        def get_orders
          [{ symbol: "NIFTY", quantity: 100, side: "BUY", status: "COMPLETED" }]
        end
      end
    end

    let(:implemented_broker) { implemented_class.new }

    it "allows complete implementation of all methods" do
      expect { implemented_broker.buy("NIFTY", 100, 50.0) }.not_to raise_error
      expect { implemented_broker.sell("NIFTY", 100, 50.0) }.not_to raise_error
      expect { implemented_broker.square_off("NIFTY", 100) }.not_to raise_error
      expect { implemented_broker.get_positions }.not_to raise_error
      expect { implemented_broker.get_orders }.not_to raise_error
    end

    it "returns expected results from implemented methods" do
      buy_result = implemented_broker.buy("NIFTY", 100, 50.0)
      expect(buy_result[:action]).to eq("BUY")
      expect(buy_result[:symbol]).to eq("NIFTY")
      expect(buy_result[:quantity]).to eq(100)
      expect(buy_result[:price]).to eq(50.0)

      sell_result = implemented_broker.sell("NIFTY", 100, 50.0)
      expect(sell_result[:action]).to eq("SELL")

      square_off_result = implemented_broker.square_off("NIFTY", 100)
      expect(square_off_result[:action]).to eq("SQUARE_OFF")

      positions = implemented_broker.get_positions
      expect(positions).to be_an(Array)
      expect(positions.first[:symbol]).to eq("NIFTY")

      orders = implemented_broker.get_orders
      expect(orders).to be_an(Array)
      expect(orders.first[:symbol]).to eq("NIFTY")
    end
  end
end
