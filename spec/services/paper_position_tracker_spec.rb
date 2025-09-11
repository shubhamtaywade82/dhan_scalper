# frozen_string_literal: true

require "spec_helper"

RSpec.describe DhanScalper::Services::PaperPositionTracker do
  let(:mock_websocket_manager) { double("WebSocketManager") }
  let(:logger) { double("Logger") }
  let(:tracker) { described_class.new(websocket_manager: mock_websocket_manager, logger: logger, memory_only: true) }

  before do
    allow(logger).to receive(:info)
    allow(logger).to receive(:debug)
    allow(logger).to receive(:warn)
    allow(logger).to receive(:error)
    allow(mock_websocket_manager).to receive(:subscribe_to_instrument)
    allow(mock_websocket_manager).to receive(:unsubscribe_from_instrument)
    allow(mock_websocket_manager).to receive(:on_price_update)
  end

  describe "#initialize" do
    it "initializes with correct attributes" do
      expect(tracker.positions).to be_a(Hash)
      expect(tracker.underlying_prices).to be_a(Hash)
      expect(tracker.websocket_manager).to eq(mock_websocket_manager)
    end

    it "sets up data directory when not memory only" do
      tracker_with_files = described_class.new(
        websocket_manager: mock_websocket_manager,
        logger: logger,
        memory_only: false,
        data_dir: "test_data"
      )
      expect(File.directory?("test_data")).to be true
    end
  end

  describe "#track_underlying" do
    let(:symbol) { "NIFTY" }
    let(:instrument_id) { "13" }

    it "subscribes to instrument and tracks price" do
      expect(mock_websocket_manager).to receive(:subscribe_to_instrument).with(instrument_id, "INDEX")
      tracker.track_underlying(symbol, instrument_id)

      expect(tracker.underlying_prices[symbol]).to include(
        instrument_id: instrument_id,
        segment: "IDX_I",
        last_price: nil
      )
    end

    it "logs the tracking action" do
      expect(logger).to receive(:info).with("[PositionTracker] Starting to track underlying: #{symbol} (#{instrument_id})")
      tracker.track_underlying(symbol, instrument_id)
    end
  end

  describe "#add_position" do
    let(:symbol) { "NIFTY" }
    let(:option_type) { "CE" }
    let(:strike) { 25_000 }
    let(:expiry) { Date.today }
    let(:instrument_id) { "TEST123" }
    let(:quantity) { 75 }
    let(:entry_price) { 150.0 }

    it "adds position to tracker" do
      tracker.add_position(symbol, option_type, strike, expiry, instrument_id, quantity, entry_price)

      position_key = "#{symbol}_#{option_type}_#{strike}_#{expiry}"
      position = tracker.positions[position_key]

      expect(position).to include(
        symbol: symbol,
        option_type: option_type,
        strike: strike,
        expiry: expiry,
        instrument_id: instrument_id,
        quantity: quantity,
        entry_price: entry_price,
        current_price: entry_price,
        pnl: 0.0,
        created_at: be_a(Time)
      )
    end

    it "subscribes to option price updates" do
      expect(mock_websocket_manager).to receive(:subscribe_to_instrument).with(instrument_id, "OPTIDX")
      tracker.add_position(symbol, option_type, strike, expiry, instrument_id, quantity, entry_price)
    end

    it "logs the position addition" do
      expect(logger).to receive(:info).with(/Position added: #{symbol} #{option_type} #{strike}/)
      tracker.add_position(symbol, option_type, strike, expiry, instrument_id, quantity, entry_price)
    end
  end

  describe "#remove_position" do
    let(:symbol) { "NIFTY" }
    let(:option_type) { "CE" }
    let(:strike) { 25_000 }
    let(:expiry) { Date.today }
    let(:instrument_id) { "TEST123" }
    let(:quantity) { 75 }
    let(:entry_price) { 150.0 }

    before do
      tracker.add_position(symbol, option_type, strike, expiry, instrument_id, quantity, entry_price)
    end

    it "removes position from tracker" do
      position_key = "#{symbol}_#{option_type}_#{strike}_#{expiry}"
      expect(tracker.positions[position_key]).not_to be_nil

      result = tracker.remove_position(position_key)
      expect(result).to be true
      expect(tracker.positions[position_key]).to be_nil
    end

    it "unsubscribes from price updates" do
      position_key = "#{symbol}_#{option_type}_#{strike}_#{expiry}"
      expect(mock_websocket_manager).to receive(:unsubscribe_from_instrument).with(instrument_id)
      tracker.remove_position(position_key)
    end

    it "logs the removal" do
      position_key = "#{symbol}_#{option_type}_#{strike}_#{expiry}"
      expect(logger).to receive(:info).with(/Position removed: #{position_key}/)
      tracker.remove_position(position_key)
    end

    it "returns false for non-existent position" do
      result = tracker.remove_position("NON_EXISTENT")
      expect(result).to be false
    end
  end

  describe "#get_underlying_price" do
    let(:symbol) { "NIFTY" }
    let(:instrument_id) { "13" }

    before do
      tracker.track_underlying(symbol, instrument_id)
    end

    it "returns cached price when available" do
      tracker.underlying_prices[symbol][:last_price] = 25_000.0
      expect(tracker.get_underlying_price(symbol)).to eq(25_000.0)
    end

    it "falls back to TickCache when no cached price" do
      tracker.underlying_prices[symbol][:last_price] = nil
      allow(DhanScalper::TickCache).to receive(:ltp).with("IDX_I", instrument_id,
                                                          use_fallback: true).and_return(25_050.0)

      expect(tracker.get_underlying_price(symbol)).to eq(25_050.0)
    end

    it "returns nil when no data available" do
      tracker.underlying_prices[symbol][:last_price] = nil
      allow(DhanScalper::TickCache).to receive(:ltp).with("IDX_I", instrument_id, use_fallback: true).and_return(nil)

      expect(tracker.get_underlying_price(symbol)).to be_nil
    end
  end

  describe "#get_position_pnl" do
    let(:symbol) { "NIFTY" }
    let(:option_type) { "CE" }
    let(:strike) { 25_000 }
    let(:expiry) { Date.today }
    let(:instrument_id) { "TEST123" }
    let(:quantity) { 75 }
    let(:entry_price) { 150.0 }

    before do
      tracker.add_position(symbol, option_type, strike, expiry, instrument_id, quantity, entry_price)
    end

    it "calculates P&L correctly for profitable position" do
      position_key = "#{symbol}_#{option_type}_#{strike}_#{expiry}"
      tracker.positions[position_key][:current_price] = 200.0

      pnl = tracker.get_position_pnl(position_key)
      expected_pnl = (200.0 - 150.0) * quantity
      expect(pnl).to eq(expected_pnl)
    end

    it "calculates P&L correctly for losing position" do
      position_key = "#{symbol}_#{option_type}_#{strike}_#{expiry}"
      tracker.positions[position_key][:current_price] = 100.0

      pnl = tracker.get_position_pnl(position_key)
      expected_pnl = (100.0 - 150.0) * quantity
      expect(pnl).to eq(expected_pnl)
    end

    it "returns nil for non-existent position" do
      pnl = tracker.get_position_pnl("NON_EXISTENT")
      expect(pnl).to be_nil
    end
  end

  describe "#get_total_pnl" do
    it "returns zero when no positions" do
      expect(tracker.get_total_pnl).to eq(0.0)
    end

    it "calculates total P&L for multiple positions" do
      # Add profitable position
      tracker.add_position("NIFTY", "CE", 25_000, Date.today, "CE123", 75, 150.0)
      position_key1 = "NIFTY_CE_25000_#{Date.today}"
      tracker.positions[position_key1][:current_price] = 200.0

      # Add losing position
      tracker.add_position("NIFTY", "PE", 25_000, Date.today, "PE123", 75, 120.0)
      position_key2 = "NIFTY_PE_25000_#{Date.today}"
      tracker.positions[position_key2][:current_price] = 100.0

      total_pnl = tracker.get_total_pnl
      expected_pnl = ((200.0 - 150.0) * 75) + ((100.0 - 120.0) * 75)
      expect(total_pnl).to eq(expected_pnl)
    end
  end

  describe "#get_positions_summary" do
    it "returns empty summary when no positions" do
      summary = tracker.get_positions_summary
      expect(summary).to include(
        total_positions: 0,
        open_positions: 0,
        closed_positions: 0,
        total_pnl: 0.0,
        winning_trades: 0,
        losing_trades: 0
      )
    end

    it "returns correct summary with positions" do
      # Add positions
      tracker.add_position("NIFTY", "CE", 25_000, Date.today, "CE123", 75, 150.0)
      tracker.add_position("NIFTY", "PE", 25_000, Date.today, "PE123", 75, 120.0)

      # Update prices
      position_key1 = "NIFTY_CE_25000_#{Date.today}"
      position_key2 = "NIFTY_PE_25000_#{Date.today}"
      tracker.positions[position_key1][:current_price] = 200.0  # Profitable
      tracker.positions[position_key2][:current_price] = 100.0  # Losing

      summary = tracker.get_positions_summary
      expect(summary[:total_positions]).to eq(2)
      expect(summary[:open_positions]).to eq(2)
      expect(summary[:winning_trades]).to eq(1)
      expect(summary[:losing_trades]).to eq(1)
    end
  end

  describe "#setup_websocket_handlers" do
    it "sets up price update handler" do
      expect(mock_websocket_manager).to receive(:on_price_update)
      tracker.setup_websocket_handlers
    end
  end

  describe "#handle_price_update" do
    let(:price_data) do
      {
        instrument_id: "13",
        segment: "IDX_I",
        ltp: 25_000.0,
        timestamp: Time.now.to_i
      }
    end

    it "updates underlying price for tracked symbols" do
      tracker.track_underlying("NIFTY", "13")
      tracker.handle_price_update(price_data)

      expect(tracker.underlying_prices["NIFTY"][:last_price]).to eq(25_000.0)
      expect(tracker.underlying_prices["NIFTY"][:last_update]).to be_a(Time)
    end

    it "updates position prices for option instruments" do
      tracker.add_position("NIFTY", "CE", 25_000, Date.today, "CE123", 75, 150.0)

      option_price_data = price_data.merge(instrument_id: "CE123", ltp: 200.0)
      tracker.handle_price_update(option_price_data)

      position_key = "NIFTY_CE_25000_#{Date.today}"
      expect(tracker.positions[position_key][:current_price]).to eq(200.0)
    end

    it "logs price updates" do
      tracker.track_underlying("NIFTY", "13")
      expect(logger).to receive(:debug).with(/Price update: NIFTY.*25000.0/)
      tracker.handle_price_update(price_data)
    end
  end

  describe "data persistence" do
    let(:tracker_with_files) do
      described_class.new(
        websocket_manager: mock_websocket_manager,
        logger: logger,
        memory_only: false,
        data_dir: "test_data"
      )
    end

    before do
      FileUtils.mkdir_p("test_data")
    end

    after do
      FileUtils.rm_rf("test_data")
    end

    it "saves positions to CSV" do
      tracker_with_files.add_position("NIFTY", "CE", 25_000, Date.today, "CE123", 75, 150.0)
      tracker_with_files.save_positions

      expect(File.exist?("test_data/positions.csv")).to be true
    end

    it "loads positions from CSV" do
      # Create test CSV
      CSV.open("test_data/positions.csv", "w") do |csv|
        csv << %w[symbol option_type strike expiry instrument_id quantity entry_price current_price pnl created_at]
        csv << ["NIFTY", "CE", "25000", Date.today.to_s, "CE123", "75", "150.0", "150.0", "0.0", Time.now.to_s]
      end

      tracker_with_files.load_positions
      expect(tracker_with_files.positions.size).to eq(1)
    end
  end

  describe "error handling" do
    it "handles WebSocket subscription errors gracefully" do
      allow(mock_websocket_manager).to receive(:subscribe_to_instrument).and_raise(StandardError, "Subscription failed")
      expect { tracker.track_underlying("NIFTY", "13") }.to raise_error(StandardError, "Subscription failed")
    end

    it "handles position calculation errors gracefully" do
      tracker.add_position("NIFTY", "CE", 25_000, Date.today, "CE123", 75, 150.0)
      position_key = "NIFTY_CE_25000_#{Date.today}"

      # Set invalid current price
      tracker.positions[position_key][:current_price] = "invalid"

      expect { tracker.get_position_pnl(position_key) }.to raise_error(ArgumentError)
    end
  end
end
