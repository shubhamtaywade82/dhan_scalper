# frozen_string_literal: true

require "spec_helper"

RSpec.describe DhanScalper::Brokers::DhanBroker do
  let(:mock_vdm) { double("VirtualDataManager") }
  let(:mock_balance_provider) { double("BalanceProvider") }
  let(:broker) { described_class.new(virtual_data_manager: mock_vdm, balance_provider: mock_balance_provider) }

  before do
    # Mock DhanHQ classes
    stub_const("DhanHQ::Models::Order", double)
    stub_const("DhanHQ::Order", double)
    stub_const("DhanHQ::Orders", double)
    stub_const("DhanHQ::Models::Trade", double)
    stub_const("DhanHQ::Trade", double)
    stub_const("DhanHQ::Models::Trades", double)
    stub_const("DhanHQ::Trades", double)

    # Mock Position class
    stub_const("DhanScalper::Position", double)
    allow(DhanScalper::Position).to receive(:new).and_return(double)

    # Mock Order struct
    stub_const("DhanScalper::Brokers::Order", Struct.new(:id, :security_id, :side, :qty, :avg_price))

    # Mock VDM methods
    allow(mock_vdm).to receive(:add_order)
    allow(mock_vdm).to receive(:add_position)
  end

  describe "#initialize" do
    it "sets instance variables correctly" do
      expect(broker.instance_variable_get(:@virtual_data_manager)).to eq(mock_vdm)
      expect(broker.instance_variable_get(:@balance_provider)).to eq(mock_balance_provider)
    end

    it "inherits from Base" do
      expect(broker).to be_a(DhanScalper::Brokers::Base)
    end
  end

  describe "#buy_market" do
    let(:order_params) do
      {
        segment: "NSE_FNO",
        security_id: "CE123",
        quantity: 150
      }
    end

    context "when order creation succeeds" do
      let(:mock_order) { double("Order", order_id: "ORDER123") }
      let(:mock_trade) { double("Trade", avg_price: 50.0) }

      before do
        allow(broker).to receive(:create_order).and_return({ order_id: "ORDER123", error: nil })
        allow(broker).to receive(:fetch_trade_price).and_return(50.0)
      end

      it "creates buy order with correct parameters" do
        result = broker.buy_market(**order_params)
        expect(result).to be_a(DhanScalper::Brokers::Order)
        expect(result.id).to eq("ORDER123")
        expect(result.security_id).to eq("CE123")
        expect(result.side).to eq("BUY")
        expect(result.qty).to eq(150)
        expect(result.avg_price).to eq(50.0)
      end

      it "logs the order to VDM" do
        expect(mock_vdm).to receive(:add_order)
        broker.buy_market(**order_params)
      end

      it "creates and logs position" do
        expect(mock_vdm).to receive(:add_position)
        broker.buy_market(**order_params)
      end
    end

    context "when order creation fails" do
      before do
        allow(broker).to receive(:create_order).and_return({ error: "Order creation failed" })
      end

      it "raises an error" do
        expect { broker.buy_market(**order_params) }.to raise_error("Order creation failed")
      end
    end

    context "when trade price fetch fails" do
      before do
        allow(broker).to receive(:create_order).and_return({ order_id: "ORDER123", error: nil })
        allow(broker).to receive(:fetch_trade_price).and_return(nil)
      end

      it "creates order with zero price" do
        result = broker.buy_market(**order_params)
        expect(result.avg_price).to eq(0.0)
      end
    end
  end

  describe "#sell_market" do
    let(:order_params) do
      {
        segment: "NSE_FNO",
        security_id: "CE123",
        quantity: 150
      }
    end

    context "when order creation succeeds" do
      let(:mock_order) { double("Order", order_id: "ORDER123") }
      let(:mock_trade) { double("Trade", avg_price: 55.0) }

      before do
        allow(broker).to receive(:create_order).and_return({ order_id: "ORDER123", error: nil })
        allow(broker).to receive(:fetch_trade_price).and_return(55.0)
      end

      it "creates sell order with correct parameters" do
        result = broker.sell_market(**order_params)
        expect(result).to be_a(DhanScalper::Brokers::Order)
        expect(result.id).to eq("ORDER123")
        expect(result.security_id).to eq("CE123")
        expect(result.side).to eq("SELL")
        expect(result.qty).to eq(150)
        expect(result.avg_price).to eq(55.0)
      end

      it "logs the order to VDM" do
        expect(mock_vdm).to receive(:add_order)
        broker.sell_market(**order_params)
      end

      it "creates and logs position" do
        expect(mock_vdm).to receive(:add_position)
        broker.sell_market(**order_params)
      end
    end

    context "when order creation fails" do
      before do
        allow(broker).to receive(:create_order).and_return({ error: "Order creation failed" })
      end

      it "raises an error" do
        expect { broker.sell_market(**order_params) }.to raise_error("Order creation failed")
      end
    end
  end

  describe "#create_order" do
    let(:params) do
      {
        transaction_type: "BUY",
        exchange_segment: "NSE_FNO",
        product_type: "MARGIN",
        order_type: "MARKET",
        validity: "DAY",
        security_id: "CE123",
        quantity: 150
      }
    end

    context "when first method succeeds" do
      before do
        allow(broker).to receive(:create_order_via_models).and_return({ order_id: "ORDER123", error: nil })
      end

      it "returns successful result from first method" do
        result = broker.send(:create_order, params)
        expect(result[:order_id]).to eq("ORDER123")
        expect(result[:error]).to be_nil
      end
    end

    context "when first method fails, second succeeds" do
      before do
        allow(broker).to receive(:create_order_via_models).and_return({ error: "Failed" })
        allow(broker).to receive(:create_order_via_direct).and_return({ order_id: "ORDER123", error: nil })
      end

      it "falls back to second method" do
        result = broker.send(:create_order, params)
        expect(result[:order_id]).to eq("ORDER123")
        expect(result[:error]).to be_nil
      end
    end

    context "when first two methods fail, third succeeds" do
      before do
        allow(broker).to receive(:create_order_via_models).and_return({ error: "Failed" })
        allow(broker).to receive(:create_order_via_direct).and_return({ error: "Failed" })
        allow(broker).to receive(:create_order_via_orders).and_return({ order_id: "ORDER123", error: nil })
      end

      it "falls back to third method" do
        result = broker.send(:create_order, params)
        expect(result[:order_id]).to eq("ORDER123")
        expect(result[:error]).to be_nil
      end
    end

    context "when all methods fail" do
      before do
        allow(broker).to receive(:create_order_via_models).and_return({ error: "Failed" })
        allow(broker).to receive(:create_order_via_direct).and_return({ error: "Failed" })
        allow(broker).to receive(:create_order_via_orders).and_return({ error: "Failed" })
      end

      it "returns error from all methods" do
        result = broker.send(:create_order, params)
        expect(result[:error]).to eq("Failed to create order via all available methods")
      end
    end
  end

  describe "#create_order_via_models" do
    let(:params) do
      {
        transaction_type: "BUY",
        exchange_segment: "NSE_FNO",
        product_type: "MARGIN",
        order_type: "MARKET",
        validity: "DAY",
        security_id: "CE123",
        quantity: 150
      }
    end

    context "when order creation succeeds" do
      let(:mock_order) { double("Order", order_id: "ORDER123", persisted?: true, errors: double(full_messages: [])) }

      before do
        allow(DhanHQ::Models::Order).to receive(:new).and_return(mock_order)
        allow(mock_order).to receive(:save)
      end

      it "creates order successfully" do
        result = broker.send(:create_order_via_models, params)
        expect(result[:order_id]).to eq("ORDER123")
        expect(result[:error]).to be_nil
      end

      it "calls save on the order" do
        expect(mock_order).to receive(:save)
        broker.send(:create_order_via_models, params)
      end
    end

    context "when order creation fails" do
      let(:mock_order) { double("Order", persisted?: false, errors: double(full_messages: ["Invalid parameters"])) }

      before do
        allow(DhanHQ::Models::Order).to receive(:new).and_return(mock_order)
        allow(mock_order).to receive(:save)
      end

      it "returns error message" do
        result = broker.send(:create_order_via_models, params)
        expect(result[:error]).to eq("Invalid parameters")
      end
    end

    context "when exception occurs" do
      before do
        allow(DhanHQ::Models::Order).to receive(:new).and_raise(StandardError, "API Error")
      end

      it "returns error message" do
        result = broker.send(:create_order_via_models, params)
        expect(result[:error]).to eq("API Error")
      end
    end
  end

  describe "#create_order_via_direct" do
    let(:params) do
      {
        transaction_type: "BUY",
        exchange_segment: "NSE_FNO",
        product_type: "MARGIN",
        order_type: "MARKET",
        validity: "DAY",
        security_id: "CE123",
        quantity: 150
      }
    end

    context "when order creation succeeds" do
      let(:mock_order) { double("Order", order_id: "ORDER123", persisted?: true, errors: double(full_messages: [])) }

      before do
        allow(DhanHQ::Order).to receive(:new).and_return(mock_order)
        allow(mock_order).to receive(:save)
      end

      it "creates order successfully" do
        result = broker.send(:create_order_via_direct, params)
        expect(result[:order_id]).to eq("ORDER123")
        expect(result[:error]).to be_nil
      end
    end

    context "when order creation fails" do
      let(:mock_order) { double("Order", persisted?: false, errors: double(full_messages: ["Invalid parameters"])) }

      before do
        allow(DhanHQ::Order).to receive(:new).and_return(mock_order)
        allow(mock_order).to receive(:save)
      end

      it "returns error message" do
        result = broker.send(:create_order_via_direct, params)
        expect(result[:error]).to eq("Invalid parameters")
      end
    end

    context "when exception occurs" do
      before do
        allow(DhanHQ::Order).to receive(:new).and_raise(StandardError, "API Error")
      end

      it "returns error message" do
        result = broker.send(:create_order_via_direct, params)
        expect(result[:error]).to eq("API Error")
      end
    end
  end

  describe "#create_order_via_orders" do
    let(:params) do
      {
        transaction_type: "BUY",
        exchange_segment: "NSE_FNO",
        product_type: "MARGIN",
        order_type: "MARKET",
        validity: "DAY",
        security_id: "CE123",
        quantity: 150
      }
    end

    context "when order creation succeeds with order_id" do
      let(:mock_order) { double("Order", order_id: "ORDER123") }

      before do
        allow(DhanHQ::Orders).to receive(:create).and_return(mock_order)
      end

      it "creates order successfully" do
        result = broker.send(:create_order_via_orders, params)
        expect(result[:order_id]).to eq("ORDER123")
        expect(result[:error]).to be_nil
      end
    end

    context "when order creation succeeds with id" do
      let(:mock_order) { double("Order", id: "ORDER123") }

      before do
        allow(DhanHQ::Orders).to receive(:create).and_return(mock_order)
      end

      it "creates order successfully using id" do
        result = broker.send(:create_order_via_orders, params)
        expect(result[:order_id]).to eq("ORDER123")
        expect(result[:error]).to be_nil
      end
    end

    context "when order creation fails" do
      before do
        allow(DhanHQ::Orders).to receive(:create).and_return(nil)
      end

      it "returns error message" do
        result = broker.send(:create_order_via_orders, params)
        expect(result[:error]).to eq("Failed to create order")
      end
    end

    context "when exception occurs" do
      before do
        allow(DhanHQ::Orders).to receive(:create).and_raise(StandardError, "API Error")
      end

      it "returns error message" do
        result = broker.send(:create_order_via_orders, params)
        expect(result[:error]).to eq("API Error")
      end
    end
  end

  describe "#fetch_trade_price" do
    let(:order_id) { "ORDER123" }

    context "when first method succeeds" do
      before do
        allow(DhanHQ::Models::Trade).to receive(:find_by_order_id).and_return(double(avg_price: 50.0))
      end

      it "returns trade price from first method" do
        result = broker.send(:fetch_trade_price, order_id)
        expect(result).to eq(50.0)
      end
    end

    context "when first method fails, second succeeds" do
      before do
        allow(DhanHQ::Models::Trade).to receive(:find_by_order_id).and_raise(StandardError, "Failed")
        allow(DhanHQ::Trade).to receive(:find_by_order_id).and_return(double(avg_price: 50.0))
      end

      it "falls back to second method" do
        result = broker.send(:fetch_trade_price, order_id)
        expect(result).to eq(50.0)
      end
    end

    context "when first two methods fail, third succeeds" do
      before do
        allow(DhanHQ::Models::Trade).to receive(:find_by_order_id).and_raise(StandardError, "Failed")
        allow(DhanHQ::Trade).to receive(:find_by_order_id).and_raise(StandardError, "Failed")
        allow(DhanHQ::Models::Trade).to receive(:find_by).and_return(double(avg_price: 50.0))
      end

      it "falls back to third method" do
        result = broker.send(:fetch_trade_price, order_id)
        expect(result).to eq(50.0)
      end
    end

    context "when first three methods fail, fourth succeeds" do
      before do
        allow(DhanHQ::Models::Trade).to receive(:find_by_order_id).and_raise(StandardError, "Failed")
        allow(DhanHQ::Trade).to receive(:find_by_order_id).and_raise(StandardError, "Failed")
        allow(DhanHQ::Models::Trade).to receive(:find_by).and_raise(StandardError, "Failed")
        allow(DhanHQ::Trade).to receive(:find_by).and_return(double(avg_price: 50.0))
      end

      it "falls back to fourth method" do
        result = broker.send(:fetch_trade_price, order_id)
        expect(result).to eq(50.0)
      end
    end

    context "when first four methods fail, fifth succeeds" do
      before do
        allow(DhanHQ::Models::Trade).to receive(:find_by_order_id).and_raise(StandardError, "Failed")
        allow(DhanHQ::Trade).to receive(:find_by_order_id).and_raise(StandardError, "Failed")
        allow(DhanHQ::Models::Trade).to receive(:find_by).and_raise(StandardError, "Failed")
        allow(DhanHQ::Trade).to receive(:find_by).and_raise(StandardError, "Failed")
        allow(DhanHQ::Models::Trades).to receive(:find_by_order_id).and_return(double(avg_price: 50.0))
      end

      it "falls back to fifth method" do
        result = broker.send(:fetch_trade_price, order_id)
        expect(result).to eq(50.0)
      end
    end

    context "when first five methods fail, sixth succeeds" do
      before do
        allow(DhanHQ::Models::Trade).to receive(:find_by_order_id).and_raise(StandardError, "Failed")
        allow(DhanHQ::Trade).to receive(:find_by_order_id).and_raise(StandardError, "Failed")
        allow(DhanHQ::Models::Trade).to receive(:find_by).and_raise(StandardError, "Failed")
        allow(DhanHQ::Trade).to receive(:find_by).and_raise(StandardError, "Failed")
        allow(DhanHQ::Models::Trades).to receive(:find_by_order_id).and_raise(StandardError, "Failed")
        allow(DhanHQ::Trades).to receive(:find_by_order_id).and_return(double(avg_price: 50.0))
      end

      it "falls back to sixth method" do
        result = broker.send(:fetch_trade_price, order_id)
        expect(result).to eq(50.0)
      end
    end

    context "when all methods fail" do
      before do
        allow(DhanHQ::Models::Trade).to receive(:find_by_order_id).and_raise(StandardError, "Failed")
        allow(DhanHQ::Trade).to receive(:find_by_order_id).and_raise(StandardError, "Failed")
        allow(DhanHQ::Models::Trade).to receive(:find_by).and_raise(StandardError, "Failed")
        allow(DhanHQ::Trade).to receive(:find_by).and_raise(StandardError, "Failed")
        allow(DhanHQ::Models::Trades).to receive(:find_by_order_id).and_raise(StandardError, "Failed")
        allow(DhanHQ::Trades).to receive(:find_by_order_id).and_raise(StandardError, "Failed")
      end

      it "returns nil" do
        result = broker.send(:fetch_trade_price, order_id)
        expect(result).to be_nil
      end
    end

    context "when method returns nil" do
      before do
        allow(DhanHQ::Models::Trade).to receive(:find_by_order_id).and_return(nil)
      end

      it "tries next method" do
        allow(DhanHQ::Trade).to receive(:find_by_order_id).and_return(double(avg_price: 50.0))
        result = broker.send(:fetch_trade_price, order_id)
        expect(result).to eq(50.0)
      end
    end

    context "when method returns object without avg_price" do
      before do
        allow(DhanHQ::Models::Trade).to receive(:find_by_order_id).and_return(double)
      end

      it "tries next method" do
        allow(DhanHQ::Trade).to receive(:find_by_order_id).and_return(double(avg_price: 50.0))
        result = broker.send(:fetch_trade_price, order_id)
        expect(result).to eq(50.0)
      end
    end
  end

  describe "error handling" do
    it "handles missing DhanHQ classes gracefully" do
      # Remove all DhanHQ constants
      Object.send(:remove_const, "DhanHQ") if defined?(DhanHQ)

      # Should not raise error during initialization
      expect { described_class.new }.not_to raise_error
    end

    it "handles missing Position class gracefully" do
      Object.send(:remove_const, "DhanScalper::Position") if defined?(DhanScalper::Position)

      # Should not raise error during initialization
      expect { described_class.new }.not_to raise_error
    end
  end

  describe "integration with VDM" do
    let(:order_params) do
      {
        segment: "NSE_FNO",
        security_id: "CE123",
        quantity: 150
      }
    end

    before do
      allow(broker).to receive(:create_order).and_return({ order_id: "ORDER123", error: nil })
      allow(broker).to receive(:fetch_trade_price).and_return(50.0)
    end

    it "logs orders to VDM" do
      expect(mock_vdm).to receive(:add_order)
      broker.buy_market(**order_params)
    end

    it "logs positions to VDM" do
      expect(mock_vdm).to receive(:add_position)
      broker.buy_market(**order_params)
    end
  end

  describe "order parameter construction" do
    let(:order_params) do
      {
        segment: "NSE_FNO",
        security_id: "CE123",
        quantity: 150
      }
    end

    it "constructs correct order parameters for buy" do
      allow(broker).to receive(:create_order).and_return({ order_id: "ORDER123", error: nil })
      allow(broker).to receive(:fetch_trade_price).and_return(50.0)

      broker.buy_market(**order_params)

      # Verify the order parameters were constructed correctly
      expect(broker).to have_received(:create_order).with(
        hash_including(
          transaction_type: "BUY",
          exchange_segment: "NSE_FNO",
          product_type: "MARGIN",
          order_type: "MARKET",
          validity: "DAY",
          security_id: "CE123",
          quantity: 150
        )
      )
    end

    it "constructs correct order parameters for sell" do
      allow(broker).to receive(:create_order).and_return({ order_id: "ORDER123", error: nil })
      allow(broker).to receive(:fetch_trade_price).and_return(50.0)

      broker.sell_market(**order_params)

      # Verify the order parameters were constructed correctly
      expect(broker).to have_received(:create_order).with(
        hash_including(
          transaction_type: "SELL",
          exchange_segment: "NSE_FNO",
          product_type: "MARGIN",
          order_type: "MARKET",
          validity: "DAY",
          security_id: "CE123",
          quantity: 150
        )
      )
    end
  end
end
