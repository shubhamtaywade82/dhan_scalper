# frozen_string_literal: true

require "spec_helper"

RSpec.describe DhanScalper::Trader do
  let(:mock_websocket) { double("WebSocket") }
  let(:mock_picker) { double("OptionPicker") }
  let(:mock_gl) { double("Global") }
  let(:mock_state) { double("State") }
  let(:mock_quantity_sizer) { double("QuantitySizer") }
  let(:mock_broker) { double("Broker") }

  let(:symbol_config) do
    {
      "seg_idx" => "IDX_I",
      "idx_sid" => "13",
      "seg_opt" => "NSE_FNO",
      "strike_step" => 50,
      "lot_size" => 75,
      "qty_multiplier" => 1
    }
  end

  let(:trader) do
    described_class.new(
      ws: mock_websocket,
      symbol: "NIFTY",
      cfg: symbol_config,
      picker: mock_picker,
      gl: mock_gl,
      state: mock_state,
      quantity_sizer: mock_quantity_sizer
    )
  end

  before do
    # Mock dependencies
    stub_const("DhanScalper::TickCache", double)
    stub_const("DhanScalper::Trend", double)
    stub_const("DhanScalper::PnL", double)

    # Mock TickCache
    allow(DhanScalper::TickCache).to receive(:ltp).and_return(19500.0)

    # Mock Trend
    allow(DhanScalper::Trend).to receive(:new).and_return(double(decide: :none))

    # Mock PnL
    allow(DhanScalper::PnL).to receive(:net).and_return(100.0)

    # Mock WebSocket
    allow(mock_websocket).to receive(:subscribe_one)

    # Mock OptionPicker
    allow(mock_picker).to receive(:nearest_strike).and_return(19500)

    # Mock Global (App)
    allow(mock_gl).to receive(:instance_variable_get).and_return(mock_broker)
    allow(mock_gl).to receive(:session_pnl_preview).and_return(0.0)
    allow(mock_gl).to receive(:session_target).and_return(1000.0)

    # Mock State
    allow(mock_state).to receive(:replace_open!)
    allow(mock_state).to receive(:push_closed!)

    # Mock QuantitySizer
    allow(mock_quantity_sizer).to receive(:calculate_lots).and_return(2)

    # Mock Broker
    allow(mock_broker).to receive(:buy_market).and_return(double(id: "ORDER123"))
    allow(mock_broker).to receive(:sell_market).and_return(double(id: "SELL123"))

    # Mock Position struct
    stub_const("DhanScalper::Trader::Position", Struct.new(:side, :sid, :entry, :qty_lots, :order_id, :best, :trail_anchor))
  end

  describe "#initialize" do
    it "sets instance variables correctly" do
      expect(trader.instance_variable_get(:@ws)).to eq(mock_websocket)
      expect(trader.instance_variable_get(:@symbol)).to eq("NIFTY")
      expect(trader.instance_variable_get(:@cfg)).to eq(symbol_config)
      expect(trader.instance_variable_get(:@picker)).to eq(mock_picker)
      expect(trader.instance_variable_get(:@gl)).to eq(mock_gl)
      expect(trader.instance_variable_get(:@state)).to eq(mock_state)
      expect(trader.instance_variable_get(:@quantity_sizer)).to eq(mock_quantity_sizer)
    end

    it "initializes with default values" do
      expect(trader.instance_variable_get(:@open)).to be_nil
      expect(trader.instance_variable_get(:@session_pnl)).to eq(0.0)
      expect(trader.instance_variable_get(:@killed)).to be false
    end

    it "subscribes to index data" do
      expect(mock_websocket).to have_received(:subscribe_one).with(
        segment: "IDX_I",
        security_id: "13"
      )
    end
  end

  describe "#subscribe_index" do
    it "subscribes to index data" do
      trader.send(:subscribe_index)
      expect(mock_websocket).to have_received(:subscribe_one).with(
        segment: "IDX_I",
        security_id: "13"
      )
    end
  end

  describe "#subscribe_options" do
    let(:ce_map) { { 19500 => "CE123" } }
    let(:pe_map) { { 19500 => "PE123" } }

    it "subscribes to all option security IDs" do
      trader.subscribe_options(ce_map, pe_map)
      expect(mock_websocket).to have_received(:subscribe_one).with(
        segment: "NSE_FNO",
        security_id: "CE123"
      )
      expect(mock_websocket).to have_received(:subscribe_one).with(
        segment: "NSE_FNO",
        security_id: "PE123"
      )
    end

    it "handles nil values gracefully" do
      trader.subscribe_options({ 19500 => nil }, { 19500 => "PE123" })
      expect(mock_websocket).to have_received(:subscribe_one).with(
        segment: "NSE_FNO",
        security_id: "PE123"
      )
    end
  end

  describe "#can_trade?" do
    context "when trader is not killed and has no open position" do
      it "returns true" do
        expect(trader.can_trade?).to be true
      end
    end

    context "when trader is killed" do
      before do
        trader.instance_variable_set(:@killed, true)
      end

      it "returns false" do
        expect(trader.can_trade?).to be false
      end
    end

    context "when trader has open position" do
      before do
        trader.instance_variable_set(:@open, double("Position"))
      end

      it "returns false" do
        expect(trader.can_trade?).to be false
      end
    end
  end

  describe "#maybe_enter" do
    let(:ce_map) { { 19500 => "CE123" } }
    let(:pe_map) { { 19500 => "PE123" } }

    context "when trader cannot trade" do
      before do
        trader.instance_variable_set(:@open, double("Position"))
      end

      it "does not enter position" do
        trader.maybe_enter(:long_ce, ce_map, pe_map)
        expect(mock_broker).not_to have_received(:buy_market)
      end
    end

    context "when no spot price available" do
      before do
        allow(DhanScalper::TickCache).to receive(:ltp).and_return(nil)
      end

      it "does not enter position" do
        trader.maybe_enter(:long_ce, ce_map, pe_map)
        expect(mock_broker).not_to have_received(:buy_market)
      end
    end

    context "when no strike mapping available" do
      before do
        allow(mock_picker).to receive(:nearest_strike).and_return(19500)
        allow(ce_map).to receive(:[]).and_return(nil)
      end

      it "does not enter position" do
        trader.maybe_enter(:long_ce, ce_map, pe_map)
        expect(mock_broker).not_to have_received(:buy_market)
      end
    end

    context "when no option LTP available" do
      before do
        allow(DhanScalper::TickCache).to receive(:ltp).and_return(19500.0, nil)
      end

      it "does not enter position" do
        trader.maybe_enter(:long_ce, ce_map, pe_map)
        expect(mock_broker).not_to have_received(:buy_market)
      end
    end

    context "when quantity sizer returns zero lots" do
      before do
        allow(mock_quantity_sizer).to receive(:calculate_lots).and_return(0)
      end

      it "does not enter position" do
        trader.maybe_enter(:long_ce, ce_map, pe_map)
        expect(mock_broker).not_to have_received(:buy_market)
      end
    end

    context "when all conditions are met for CE entry" do
      before do
        allow(DhanScalper::TickCache).to receive(:ltp).and_return(19500.0, 50.0)
        allow(mock_quantity_sizer).to receive(:calculate_lots).and_return(2)
        allow(mock_broker).to receive(:buy_market).and_return(double(id: "ORDER123"))
      end

      it "enters long CE position" do
        trader.maybe_enter(:long_ce, ce_map, pe_map)
        expect(mock_broker).to have_received(:buy_market).with(
          segment: "NSE_FNO",
          security_id: "CE123",
          quantity: 150
        )
      end

      it "creates position record" do
        trader.maybe_enter(:long_ce, ce_map, pe_map)
        expect(trader.instance_variable_get(:@open)).not_to be_nil
        expect(trader.instance_variable_get(:@open).side).to eq("BUY_CE")
      end
    end

    context "when all conditions are met for PE entry" do
      before do
        allow(DhanScalper::TickCache).to receive(:ltp).and_return(19500.0, 50.0)
        allow(mock_quantity_sizer).to receive(:calculate_lots).and_return(2)
        allow(mock_broker).to receive(:buy_market).and_return(double(id: "ORDER123"))
      end

      it "enters long PE position" do
        trader.maybe_enter(:long_pe, ce_map, pe_map)
        expect(mock_broker).to have_received(:buy_market).with(
          segment: "NSE_FNO",
          security_id: "PE123",
          quantity: 150
        )
      end

      it "creates position record" do
        trader.maybe_enter(:long_pe, ce_map, pe_map)
        expect(trader.instance_variable_get(:@open)).not_to be_nil
        expect(trader.instance_variable_get(:@open).side).to eq("BUY_PE")
      end
    end

    context "when order placement fails" do
      before do
        allow(DhanScalper::TickCache).to receive(:ltp).and_return(19500.0, 50.0)
        allow(mock_quantity_sizer).to receive(:calculate_lots).and_return(2)
        allow(mock_broker).to receive(:buy_market).and_return(nil)
      end

      it "does not create position" do
        trader.maybe_enter(:long_ce, ce_map, pe_map)
        expect(trader.instance_variable_get(:@open)).to be_nil
      end
    end
  end

  describe "#manage_open" do
    let(:position) do
      DhanScalper::Trader::Position.new("BUY_CE", "CE123", 50.0, 2, "ORDER123", 0.0, 50.0)
    end

    before do
      trader.instance_variable_set(:@open, position)
      allow(DhanScalper::TickCache).to receive(:ltp).and_return(55.0)
      allow(DhanScalper::PnL).to receive(:net).and_return(100.0)
    end

    context "when no LTP available" do
      before do
        allow(DhanScalper::TickCache).to receive(:ltp).and_return(nil)
      end

      it "does not manage position" do
        trader.manage_open(tp_pct: 0.35, sl_pct: 0.18, trail_pct: 0.12, charge_per_order: 20.0)
        expect(mock_broker).not_to have_received(:sell_market)
      end
    end

    context "when take profit is hit" do
      before do
        allow(DhanScalper::TickCache).to receive(:ltp).and_return(67.5) # 50 * 1.35
      end

      it "closes position with TP reason" do
        trader.manage_open(tp_pct: 0.35, sl_pct: 0.18, trail_pct: 0.12, charge_per_order: 20.0)
        expect(mock_broker).to have_received(:sell_market).with(
          segment: "NSE_FNO",
          security_id: "CE123",
          quantity: 150
        )
      end
    end

    context "when stop loss is hit" do
      before do
        allow(DhanScalper::TickCache).to receive(:ltp).and_return(41.0) # 50 * 0.82
      end

      it "closes position with SL reason" do
        trader.manage_open(tp_pct: 0.35, sl_pct: 0.18, trail_pct: 0.12, charge_per_order: 20.0)
        expect(mock_broker).to have_received(:sell_market).with(
          segment: "NSE_FNO",
          security_id: "CE123",
          quantity: 150
        )
      end
    end

    context "when trailing stop is hit" do
      before do
        # Set up trailing stop scenario
        position.best = 100.0
        position.trail_anchor = 60.0
        allow(DhanScalper::TickCache).to receive(:ltp).and_return(55.0)
      end

      it "closes position with TRAIL reason" do
        trader.manage_open(tp_pct: 0.35, sl_pct: 0.18, trail_pct: 0.12, charge_per_order: 20.0)
        expect(mock_broker).to have_received(:sell_market).with(
          segment: "NSE_FNO",
          security_id: "CE123",
          quantity: 150
        )
      end
    end

    context "when technical invalidation occurs" do
      before do
        allow(DhanScalper::Trend).to receive(:new).and_return(double(decide: :long_pe))
      end

      it "closes position with TECH_INVALID reason" do
        trader.manage_open(tp_pct: 0.35, sl_pct: 0.18, trail_pct: 0.12, charge_per_order: 20.0)
        expect(mock_broker).to have_received(:sell_market).with(
          segment: "NSE_FNO",
          security_id: "CE123",
          quantity: 150
        )
      end
    end

    context "when position remains open" do
      before do
        allow(DhanScalper::TickCache).to receive(:ltp).and_return(55.0)
        allow(DhanScalper::PnL).to receive(:net).and_return(100.0)
      end

      it "updates best PnL if current is higher" do
        trader.manage_open(tp_pct: 0.35, sl_pct: 0.18, trail_pct: 0.12, charge_per_order: 20.0)
        expect(position.best).to eq(100.0)
      end

      it "updates trailing anchor when conditions are met" do
        allow(DhanScalper::TickCache).to receive(:ltp).and_return(62.0) # Above trail trigger
        trader.manage_open(tp_pct: 0.35, sl_pct: 0.18, trail_pct: 0.12, charge_per_order: 20.0)
        expect(position.trail_anchor).to be > 0
      end
    end
  end

  describe "#close!" do
    let(:position) do
      DhanScalper::Trader::Position.new("BUY_CE", "CE123", 50.0, 2, "ORDER123", 0.0, 50.0)
    end

    before do
      trader.instance_variable_set(:@open, position)
      allow(mock_broker).to receive(:sell_market).and_return(double(id: "SELL123"))
      allow(DhanScalper::PnL).to receive(:net).and_return(100.0)
    end

    context "when broker is not available" do
      before do
        allow(mock_gl).to receive(:instance_variable_get).and_return(nil)
      end

      it "logs error and does not close position" do
        expect { trader.close!("TP", 55.0, 20.0) }.not_to raise_error
        expect(trader.instance_variable_get(:@open)).to eq(position)
      end
    end

    context "when sell order fails" do
      before do
        allow(mock_broker).to receive(:sell_market).and_return(nil)
      end

      it "logs error and does not close position" do
        expect { trader.close!("TP", 55.0, 20.0) }.not_to raise_error
        expect(trader.instance_variable_get(:@open)).to eq(position)
      end
    end

    context "when sell order succeeds" do
      it "closes the position" do
        trader.close!("TP", 55.0, 20.0)
        expect(trader.instance_variable_get(:@open)).to be_nil
      end

      it "updates session PnL" do
        initial_pnl = trader.session_pnl
        trader.close!("TP", 55.0, 20.0)
        expect(trader.session_pnl).to eq(initial_pnl + 100.0)
      end

      it "publishes closed position to state" do
        expect(mock_state).to receive(:push_closed!).with(
          symbol: "NIFTY",
          side: "BUY_CE",
          reason: "TP",
          entry: 50.0,
          exit_price: 55.0,
          net: 100.0
        )
        trader.close!("TP", 55.0, 20.0)
      end

      it "publishes open snapshot to state" do
        expect(mock_state).to receive(:replace_open!).with([])
        trader.close!("TP", 55.0, 20.0)
      end
    end
  end

  describe "#kill!" do
    it "sets killed flag to true" do
      trader.kill!
      expect(trader.instance_variable_get(:@killed)).to be true
    end
  end

  describe "#publish_open_snapshot!" do
    let(:position) do
      DhanScalper::Trader::Position.new("BUY_CE", "CE123", 50.0, 2, "ORDER123", 0.0, 50.0)
    end

    before do
      trader.instance_variable_set(:@open, position)
      allow(DhanScalper::TickCache).to receive(:ltp).and_return(55.0)
      allow(DhanScalper::PnL).to receive(:net).and_return(100.0)
    end

    context "when state is available" do
      it "publishes open position snapshot" do
        expect(mock_state).to receive(:replace_open!).with([{
          symbol: "NIFTY",
          sid: "CE123",
          side: "BUY_CE",
          qty_lots: 2,
          entry: 50.0,
          ltp: 55.0,
          net: 100.0,
          best: 0.0
        }])
        trader.send(:publish_open_snapshot!)
      end
    end

    context "when state is not available" do
      before do
        trader.instance_variable_set(:@state, nil)
      end

      it "does not raise error" do
        expect { trader.send(:publish_open_snapshot!) }.not_to raise_error
      end
    end
  end

  describe "#publish_closed!" do
    let(:position) do
      DhanScalper::Trader::Position.new("BUY_CE", "CE123", 50.0, 2, "ORDER123", 0.0, 50.0)
    end

    before do
      trader.instance_variable_set(:@open, position)
    end

    context "when state is available" do
      it "publishes closed position" do
        expect(mock_state).to receive(:push_closed!).with(
          symbol: "NIFTY",
          side: "BUY_CE",
          reason: "TP",
          entry: 50.0,
          exit_price: 55.0,
          net: 100.0
        )
        trader.send(:publish_closed!, reason: "TP", exit_price: 55.0, net: 100.0)
      end
    end

    context "when state is not available" do
      before do
        trader.instance_variable_set(:@state, nil)
      end

      it "does not raise error" do
        expect { trader.send(:publish_closed!, reason: "TP", exit_price: 55.0, net: 100.0) }.not_to raise_error
      end
    end
  end

  describe "#opposite_signal?" do
    context "when current position is BUY_CE and signal is long_pe" do
      let(:position) do
        DhanScalper::Trader::Position.new("BUY_CE", "CE123", 50.0, 2, "ORDER123", 0.0, 50.0)
      end

      before do
        trader.instance_variable_set(:@open, position)
        allow(DhanScalper::Trend).to receive(:new).and_return(double(decide: :long_pe))
      end

      it "returns true" do
        expect(trader.send(:opposite_signal?)).to be true
      end
    end

    context "when current position is BUY_PE and signal is long_ce" do
      let(:position) do
        DhanScalper::Trader::Position.new("BUY_PE", "PE123", 50.0, 2, "ORDER123", 0.0, 50.0)
      end

      before do
        trader.instance_variable_set(:@open, position)
        allow(DhanScalper::Trend).to receive(:new).and_return(double(decide: :long_ce))
      end

      it "returns true" do
        expect(trader.send(:opposite_signal?)).to be true
      end
    end

    context "when signals are not opposite" do
      let(:position) do
        DhanScalper::Trader::Position.new("BUY_CE", "CE123", 50.0, 2, "ORDER123", 0.0, 50.0)
      end

      before do
        trader.instance_variable_set(:@open, position)
        allow(DhanScalper::Trend).to receive(:new).and_return(double(decide: :long_ce))
      end

      it "returns false" do
        expect(trader.send(:opposite_signal?)).to be false
      end
    end

    context "when trend analysis fails" do
      let(:position) do
        DhanScalper::Trader::Position.new("BUY_CE", "CE123", 50.0, 2, "ORDER123", 0.0, 50.0)
      end

      before do
        trader.instance_variable_set(:@open, position)
        allow(DhanScalper::Trend).to receive(:new).and_raise(StandardError, "Trend analysis failed")
      end

      it "returns false" do
        expect(trader.send(:opposite_signal?)).to be false
      end
    end
  end

  describe "PnL module" do
    describe ".round_trip_orders" do
      it "calculates round trip order charges" do
        expect(DhanScalper::PnL.round_trip_orders(20.0)).to eq(40.0)
      end
    end

    describe ".net" do
      it "calculates net PnL with charges" do
        result = DhanScalper::PnL.net(
          entry: 50.0,
          ltp: 55.0,
          lot_size: 75,
          qty_lots: 2,
          charge_per_order: 20.0
        )
        expect(result).to eq(100.0)
      end
    end
  end

  describe "Trend class" do
    let(:trend) { DhanScalper::Trend.new(seg_idx: "IDX_I", sid_idx: "13") }

    before do
      stub_const("DhanScalper::CandleSeries", double)
      allow(DhanScalper::CandleSeries).to receive(:load_from_dhan_intraday).and_return(
        double(candles: Array.new(60) { double }, ema: [100.0, 101.0], rsi: [55.0, 56.0])
      )
    end

    it "initializes with segment and security ID" do
      expect(trend.instance_variable_get(:@seg_idx)).to eq("IDX_I")
      expect(trend.instance_variable_get(:@sid_idx)).to eq("13")
    end

    it "decides based on technical indicators" do
      result = trend.decide
      expect(result).to eq(:none)
    end
  end
end
