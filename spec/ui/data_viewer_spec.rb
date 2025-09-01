# frozen_string_literal: true

require "spec_helper"

RSpec.describe DhanScalper::UI::DataViewer do
  let(:data_viewer) { described_class.new }

  before do
    # Mock dependencies
    stub_const("DhanScalper::VirtualDataManager", double)
    stub_const("TTY::Screen", double)
    stub_const("TTY::Cursor", double)
    stub_const("Pastel", double)

    # Mock VirtualDataManager
    allow(DhanScalper::VirtualDataManager).to receive(:new).and_return(mock_vdm)

    # Mock TTY::Screen
    allow(TTY::Screen).to receive(:width).and_return(80)

    # Mock TTY::Cursor
    allow(TTY::Cursor).to receive(:new).and_return(mock_cursor)

    # Mock Pastel
    allow(Pastel).to receive(:new).and_return(mock_pastel)
  end

  let(:mock_vdm) { double("VirtualDataManager") }
  let(:mock_cursor) { double("Cursor") }
  let(:mock_pastel) { double("Pastel") }

  before do
    # Mock VDM methods
    allow(mock_vdm).to receive(:get_balance).and_return(mock_balance)
    allow(mock_vdm).to receive(:get_positions).and_return(mock_positions)
    allow(mock_vdm).to receive(:get_orders).and_return(mock_orders)

    # Mock cursor methods
    allow(mock_cursor).to receive(:hide)
    allow(mock_cursor).to receive(:show)

    # Mock pastel methods
    allow(mock_pastel).to receive(:green).and_return("GREEN")
    allow(mock_pastel).to receive(:red).and_return("RED")
    allow(mock_pastel).to receive(:blue).and_return("BLUE")
    allow(mock_pastel).to receive(:yellow).and_return("YELLOW")
    allow(mock_pastel).to receive(:dim).and_return("DIM")

    # Mock balance data
    allow(mock_balance).to receive(:[]).with(:available).and_return(100_000.0)
    allow(mock_balance).to receive(:[]).with(:used).and_return(50_000.0)
    allow(mock_balance).to receive(:[]).with(:total).and_return(150_000.0)

    # Mock positions data
    allow(mock_positions).to receive(:empty?).and_return(false)
    allow(mock_positions).to receive(:map).and_return(mock_position_rows)

    # Mock orders data
    allow(mock_orders).to receive(:empty?).and_return(false)
    allow(mock_orders).to receive(:map).and_return(mock_order_rows)

    # Mock TTY::Box
    stub_const("TTY::Box", double)
    allow(TTY::Box).to receive(:frame).and_return("BOXED_CONTENT")

    # Mock TTY::Table
    stub_const("TTY::Table", double)
    allow(TTY::Table).to receive(:new).and_return(mock_table)
    allow(mock_table).to receive(:render).and_return("TABLE_CONTENT")
  end

  let(:mock_balance) { double("Balance") }
  let(:mock_positions) { double("Positions") }
  let(:mock_orders) { double("Orders") }
  let(:mock_table) { double("Table") }
  let(:mock_position_rows) { [["NIFTY", "BUY", "100", "₹100.0", "₹105.0", "₹500.0"]] }
  let(:mock_order_rows) { [["ORDER123...", "BUY", "100", "₹100.0", "10:30:15"]] }

  describe "#initialize" do
    it "sets instance variables correctly" do
      expect(data_viewer.instance_variable_get(:@pastel)).to eq(mock_pastel)
      expect(data_viewer.instance_variable_get(:@vdm)).to eq(mock_vdm)
      expect(data_viewer.instance_variable_get(:@cursor)).to eq(mock_cursor)
      expect(data_viewer.instance_variable_get(:@alive)).to be true
    end

    it "creates VirtualDataManager instance" do
      expect(DhanScalper::VirtualDataManager).to have_received(:new)
    end

    it "creates Pastel instance" do
      expect(Pastel).to have_received(:new)
    end

    it "creates TTY::Cursor instance" do
      expect(TTY::Cursor).to receive(:new)
    end
  end

  describe "#run" do
    before do
      # Mock the main loop to run only once
      allow(data_viewer).to receive(:render_frame)
      allow(data_viewer).to receive(:sleep)
      allow(data_viewer).to receive(:trap_signals)
      allow(data_viewer).to receive(:hide_cursor)
      allow(data_viewer).to receive(:show_cursor)
    end

    it "sets up signal handling" do
      expect(data_viewer).to receive(:trap_signals)
      data_viewer.run
    end

    it "hides cursor initially" do
      expect(data_viewer).to receive(:hide_cursor)
      data_viewer.run
    end

    it "shows cursor when finished" do
      expect(data_viewer).to receive(:show_cursor)
      data_viewer.run
    end

    it "renders frames in loop" do
      expect(data_viewer).to receive(:render_frame)
      data_viewer.run
    end

    it "sleeps between frames" do
      expect(data_viewer).to receive(:sleep).with(5)
      data_viewer.run
    end

    context "when interrupted" do
      before do
        allow(data_viewer).to receive(:render_frame).and_raise(Interrupt)
      end

      it "handles Interrupt gracefully" do
        expect { data_viewer.run }.not_to raise_error
      end

      it "shows cursor when interrupted" do
        expect(data_viewer).to receive(:show_cursor)
        data_viewer.run
      end
    end
  end

  describe "#trap_signals" do
    it "sets up INT signal handler" do
      expect(Signal).to receive(:trap).with("INT")
      data_viewer.send(:trap_signals)
    end

    it "sets up TERM signal handler" do
      expect(Signal).to receive(:trap).with("TERM")
      data_viewer.send(:trap_signals)
    end

    it "sets @alive to false when signal received" do
      # Mock signal handler
      allow(Signal).to receive(:trap).with("INT").and_yield
      allow(Signal).to receive(:trap).with("TERM").and_yield

      data_viewer.send(:trap_signals)
      expect(data_viewer.instance_variable_get(:@alive)).to be false
    end
  end

  describe "#hide_cursor" do
    it "hides cursor using ANSI escape sequence" do
      expect { data_viewer.send(:hide_cursor) }.to output("\e[?25l").to_stdout
    end
  end

  describe "#show_cursor" do
    it "shows cursor using ANSI escape sequence" do
      expect { data_viewer.send(:show_cursor) }.to output("\e[?25h").to_stdout
    end
  end

  describe "#clear_screen" do
    it "clears screen using ANSI escape sequence" do
      expect { data_viewer.send(:clear_screen) }.to output("\e[2J\e[H").to_stdout
    end
  end

  describe "#render_frame" do
    before do
      allow(data_viewer).to receive(:header_box).and_return("HEADER")
      allow(data_viewer).to receive(:balance_box).and_return("BALANCE")
      allow(data_viewer).to receive(:positions_box).and_return("POSITIONS")
      allow(data_viewer).to receive(:recent_orders_box).and_return("ORDERS")
      allow(data_viewer).to receive(:footer_hint).and_return("FOOTER")
    end

    it "renders all components" do
      expect(data_viewer).to receive(:header_box).with(80)
      expect(data_viewer).to receive(:balance_box).with(80)
      expect(data_viewer).to receive(:positions_box).with(80)
      expect(data_viewer).to receive(:recent_orders_box).with(80)
      expect(data_viewer).to receive(:footer_hint).with(80)
      data_viewer.send(:render_frame)
    end

    it "outputs all components" do
      expect { data_viewer.send(:render_frame) }.to output("HEADERBALANCEPOSITIONSORDERSFOOTER").to_stdout
    end
  end

  describe "#header_box" do
    it "creates header box with correct title" do
      expect(TTY::Box).to receive(:frame).with(
        width: 80,
        title: { top_left: " DHAN SCALPER - VIRTUAL DATA DASHBOARD " },
        style: { border: { fg: :bright_blue } }
      )
      data_viewer.send(:header_box, 80)
    end

    it "returns boxed content" do
      result = data_viewer.send(:header_box, 80)
      expect(result).to eq("BOXED_CONTENT")
    end
  end

  describe "#balance_box" do
    it "creates balance box with correct title" do
      expect(TTY::Box).to receive(:frame).with(
        width: 80,
        title: { top_left: " 💰 ACCOUNT BALANCE " },
        style: { border: { fg: :bright_green } }
      )
      data_viewer.send(:balance_box, 80)
    end

    it "formats balance information correctly" do
      expect(mock_pastel).to receive(:green).with("₹100000.0")
      expect(mock_pastel).to receive(:red).with("₹50000.0")
      expect(mock_pastel).to receive(:blue).with("₹150000.0")
      data_viewer.send(:balance_box, 80)
    end

    it "returns boxed content" do
      result = data_viewer.send(:balance_box, 80)
      expect(result).to eq("BOXED_CONTENT")
    end
  end

  describe "#positions_box" do
    context "when positions exist" do
      before do
        allow(mock_positions).to receive(:empty?).and_return(false)
        allow(mock_positions).to receive(:map).and_return(mock_position_rows)
      end

      it "creates positions box with correct title" do
        expect(TTY::Box).to receive(:frame).with(
          width: 80,
          title: { top_left: " 📊 POSITIONS " },
          style: { border: { fg: :bright_black } }
        )
        data_viewer.send(:positions_box, 80)
      end

      it "creates table with correct headers" do
        expect(TTY::Table).to receive(:new).with(
          ["Symbol", "Side", "Qty", "Entry", "Current", "P&L"],
          mock_position_rows
        )
        data_viewer.send(:positions_box, 80)
      end

      it "renders table with ASCII format" do
        expect(mock_table).to receive(:render).with(:ascii, resize: true)
        data_viewer.send(:positions_box, 80)
      end
    end

    context "when no positions exist" do
      before do
        allow(mock_positions).to receive(:empty?).and_return(true)
      end

      it "creates box with no positions message" do
        expect(TTY::Box).to receive(:frame).with(
          width: 80,
          title: { top_left: " 📊 POSITIONS " },
          style: { border: { fg: :bright_black } }
        )
        data_viewer.send(:positions_box, 80)
      end

      it "shows yellow no positions message" do
        expect(mock_pastel).to receive(:yellow).with("No open positions")
        data_viewer.send(:positions_box, 80)
      end
    end
  end

  describe "#recent_orders_box" do
    context "when orders exist" do
      before do
        allow(mock_orders).to receive(:empty?).and_return(false)
        allow(mock_orders).to receive(:map).and_return(mock_order_rows)
      end

      it "creates orders box with correct title" do
        expect(TTY::Box).to receive(:frame).with(
          width: 80,
          title: { top_left: " 📋 RECENT ORDERS " },
          style: { border: { fg: :bright_black } }
        )
        data_viewer.send(:recent_orders_box, 80)
      end

      it "creates table with correct headers" do
        expect(TTY::Table).to receive(:new).with(
          %w[ID Side Qty Price Time],
          mock_order_rows
        )
        data_viewer.send(:recent_orders_box, 80)
      end

      it "renders table with ASCII format" do
        expect(mock_table).to receive(:render).with(:ascii, resize: true)
        data_viewer.send(:recent_orders_box, 80)
      end
    end

    context "when no orders exist" do
      before do
        allow(mock_orders).to receive(:empty?).and_return(true)
      end

      it "creates box with no orders message" do
        expect(TTY::Box).to receive(:frame).with(
          width: 80,
          title: { top_left: " 📋 RECENT ORDERS " },
          style: { border: { fg: :bright_black } }
        )
        data_viewer.send(:recent_orders_box, 80)
      end

      it "shows yellow no orders message" do
        expect(mock_pastel).to receive(:yellow).with("No orders found")
        data_viewer.send(:recent_orders_box, 80)
      end
    end
  end

  describe "#footer_hint" do
    it "returns dimmed footer text" do
      expect(mock_pastel).to receive(:dim).with("Press Ctrl+C to exit | Data refreshes every 5 seconds")
      data_viewer.send(:footer_hint, 80)
    end
  end

  describe "position data formatting" do
    let(:mock_position) do
      {
        symbol: "NIFTY",
        side: "BUY",
        quantity: 100,
        entry_price: 100.0,
        current_price: 105.0,
        pnl: 500.0
      }
    end

    before do
      allow(mock_positions).to receive(:empty?).and_return(false)
      allow(mock_positions).to receive(:map).and_return([mock_position])
    end

    it "formats position data correctly" do
      expect(mock_positions).to receive(:map) do |&block|
        expect(block.call(mock_position)).to eq([
          "NIFTY",
          "BUY",
          100,
          "₹100.0",
          "₹105.0",
          "₹500.0"
        ])
        [["NIFTY", "BUY", "100", "₹100.0", "₹105.0", "₹500.0"]]
      end
      data_viewer.send(:positions_box, 80)
    end

    it "handles different position sides" do
      buy_position = mock_position.merge(side: "BUY")
      sell_position = mock_position.merge(side: "SELL")

      allow(mock_positions).to receive(:map).and_return([buy_position, sell_position])

      expect(mock_pastel).to receive(:green).with("BUY")
      expect(mock_pastel).to receive(:red).with("SELL")
      data_viewer.send(:positions_box, 80)
    end

    it "handles different PnL values" do
      profitable_position = mock_position.merge(pnl: 500.0)
      loss_position = mock_position.merge(pnl: -300.0)

      allow(mock_positions).to receive(:map).and_return([profitable_position, loss_position])

      expect(mock_pastel).to receive(:green).with("₹500.0")
      expect(mock_pastel).to receive(:red).with("₹-300.0")
      data_viewer.send(:positions_box, 80)
    end
  end

  describe "order data formatting" do
    let(:mock_order) do
      {
        id: "ORDER123456789",
        side: "BUY",
        quantity: 100,
        avg_price: 100.0,
        timestamp: "2024-01-25T10:30:15Z"
      }
    end

    before do
      allow(mock_orders).to receive(:empty?).and_return(false)
      allow(mock_orders).to receive(:map).and_return([mock_order])
    end

    it "formats order data correctly" do
      expect(mock_orders).to receive(:map) do |&block|
        expect(block.call(mock_order)).to eq([
          "ORDER123...",
          "BUY",
          100,
          "₹100.0",
          "10:30:15"
        ])
        [["ORDER123...", "BUY", "100", "₹100.0", "10:30:15"]]
      end
      data_viewer.send(:recent_orders_box, 80)
    end

    it "truncates long order IDs" do
      long_id_order = mock_order.merge(id: "VERY_LONG_ORDER_ID_THAT_SHOULD_BE_TRUNCATED")
      allow(mock_orders).to receive(:map).and_return([long_id_order])

      expect(mock_orders).to receive(:map) do |&block|
        result = block.call(long_id_order)
        expect(result[0]).to eq("VERY_LONG...")
        [result]
      end
      data_viewer.send(:recent_orders_box, 80)
    end

    it "formats timestamp correctly" do
      # Mock Time.parse to return a specific time
      allow(Time).to receive(:parse).with("2024-01-25T10:30:15Z").and_return(Time.new(2024, 1, 25, 10, 30, 15))

      expect(mock_orders).to receive(:map) do |&block|
        result = block.call(mock_order)
        expect(result[4]).to eq("10:30:15")
        [result]
      end
      data_viewer.send(:recent_orders_box, 80)
    end
  end

  describe "error handling" do
    it "handles VDM errors gracefully" do
      allow(mock_vdm).to receive(:get_balance).and_raise(StandardError, "VDM Error")
      expect { data_viewer.send(:balance_box, 80) }.not_to raise_error
    end

    it "handles missing methods gracefully" do
      incomplete_vdm = double
      allow(DhanScalper::VirtualDataManager).to receive(:new).and_return(incomplete_vdm)
      data_viewer = described_class.new

      expect { data_viewer.send(:balance_box, 80) }.not_to raise_error
    end
  end

  describe "refresh rate" do
    it "uses correct refresh interval" do
      expect(described_class::REFRESH).to eq(5)
    end
  end

  describe "screen width handling" do
    it "gets screen width from TTY::Screen" do
      expect(TTY::Screen).to receive(:width)
      data_viewer.send(:render_frame)
    end

    it "handles different screen widths" do
      allow(TTY::Screen).to receive(:width).and_return(120)
      expect(data_viewer).to receive(:header_box).with(120)
      data_viewer.send(:render_frame)
    end
  end

  describe "signal handling integration" do
    it "stops rendering when signal received" do
      # Mock signal to set @alive to false
      allow(Signal).to receive(:trap).with("INT") do |&block|
        data_viewer.instance_variable_set(:@alive, false)
      end
      allow(Signal).to receive(:trap).with("TERM")

      data_viewer.send(:trap_signals)
      expect(data_viewer.instance_variable_get(:@alive)).to be false
    end
  end

  describe "cursor management integration" do
    it "hides cursor before rendering" do
      expect(data_viewer).to receive(:hide_cursor)
      data_viewer.run
    end

    it "shows cursor after rendering" do
      expect(data_viewer).to receive(:show_cursor)
      data_viewer.run
    end
  end

  describe "data refresh integration" do
    it "refreshes data on each render" do
      expect(mock_vdm).to receive(:get_balance)
      expect(mock_vdm).to receive(:get_positions)
      expect(mock_vdm).to receive(:get_orders)
      data_viewer.send(:render_frame)
    end
  end
end
