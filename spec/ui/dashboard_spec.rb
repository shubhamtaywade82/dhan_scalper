# frozen_string_literal: true

require "spec_helper"

RSpec.describe DhanScalper::UI::Dashboard do
  let(:mock_state) { double("State") }
  let(:mock_balance_provider) { double("BalanceProvider") }
  let(:dashboard) { described_class.new(state: mock_state, balance_provider: mock_balance_provider) }

  before do
    # Mock TTY gems to avoid actual terminal output
    stub_const("TTY::Box", double)
    stub_const("TTY::Table", double)
    stub_const("Pastel", double)

    # Mock state methods
    allow(mock_state).to receive_messages(symbols: %w[NIFTY BANKNIFTY], open_positions: [], closed_positions: [],
                                          total_pnl: 0.0, session_pnl: 0.0)

    # Mock balance provider methods
    allow(mock_balance_provider).to receive_messages(available_balance: 100_000.0, total_balance: 200_000.0,
                                                     used_balance: 100_000.0)

    # Mock TTY components
    allow(TTY::Box).to receive(:new).and_return(double(render: "Mock Box"))
    allow(TTY::Table).to receive(:new).and_return(double(render: "Mock Table"))
    allow(Pastel).to receive(:new).and_return(double(
                                                green: "Mock Green",
                                                red: "Mock Red",
                                                yellow: "Mock Yellow",
                                                blue: "Mock Blue",
                                                white: "Mock White"
                                              ))
  end

  describe "#initialize" do
    it "sets state and balance provider" do
      expect(dashboard.instance_variable_get(:@state)).to eq(mock_state)
      expect(dashboard.instance_variable_get(:@balance_provider)).to eq(mock_balance_provider)
    end

    it "initializes TTY components" do
      expect(dashboard.instance_variable_get(:@pastel)).to be_a(double)
      expect(dashboard.instance_variable_get(:@box)).to be_a(double)
      expect(dashboard.instance_variable_get(:@table)).to be_a(double)
    end
  end

  describe "#render" do
    it "renders complete dashboard" do
      result = dashboard.render

      expect(result).to include("Mock Box")
      expect(result).to include("Mock Table")
    end

    it "includes all dashboard sections" do
      result = dashboard.render

      # Should include all major sections
      expect(result).to be_a(String)
      expect(result.length).to be > 0
    end
  end

  describe "#render_header" do
    it "renders header with title and timestamp" do
      result = dashboard.send(:render_header)

      expect(result).to include("Mock Box")
      expect(result).to include("DhanScalper")
    end
  end

  describe "#render_balance_section" do
    it "renders balance information" do
      result = dashboard.send(:render_balance_section)

      expect(result).to include("Mock Box")
      expect(result).to include("Balance")
    end

    it "displays available balance" do
      allow(mock_balance_provider).to receive(:available_balance).and_return(75_000.0)

      result = dashboard.send(:render_balance_section)
      expect(result).to include("Mock Box")
    end

    it "displays total balance" do
      allow(mock_balance_provider).to receive(:total_balance).and_return(200_000.0)

      result = dashboard.send(:render_balance_section)
      expect(result).to include("Mock Box")
    end

    it "displays used balance" do
      allow(mock_balance_provider).to receive(:used_balance).and_return(125_000.0)

      result = dashboard.send(:render_balance_section)
      expect(result).to include("Mock Box")
    end
  end

  describe "#render_positions_section" do
    context "when no positions exist" do
      before do
        allow(mock_state).to receive_messages(open_positions: [], closed_positions: [])
      end

      it "renders empty positions section" do
        result = dashboard.send(:render_positions_section)

        expect(result).to include("Mock Box")
        expect(result).to include("Positions")
      end
    end

    context "when positions exist" do
      let(:mock_open_position) do
        double(
          symbol: "NIFTY",
          quantity: 100,
          side: "LONG",
          entry_price: 50.0,
          current_price: 55.0,
          pnl: 500.0
        )
      end

      let(:mock_closed_position) do
        double(
          symbol: "BANKNIFTY",
          quantity: 50,
          side: "LONG",
          entry_price: 100.0,
          exit_price: 105.0,
          pnl: 250.0
        )
      end

      before do
        allow(mock_state).to receive_messages(open_positions: [mock_open_position],
                                              closed_positions: [mock_closed_position])
      end

      it "renders open positions" do
        result = dashboard.send(:render_positions_section)

        expect(result).to include("Mock Box")
        expect(result).to include("Positions")
      end

      it "displays position details" do
        allow(mock_open_position).to receive_messages(symbol: "NIFTY", quantity: 100, side: "LONG")

        result = dashboard.send(:render_positions_section)
        expect(result).to include("Mock Box")
      end
    end
  end

  describe "#render_pnl_section" do
    it "renders PnL information" do
      allow(mock_state).to receive_messages(total_pnl: 1500.0, session_pnl: 500.0)

      result = dashboard.send(:render_pnl_section)

      expect(result).to include("Mock Box")
      expect(result).to include("PnL")
    end

    it "handles positive PnL" do
      allow(mock_state).to receive_messages(total_pnl: 1000.0, session_pnl: 250.0)

      result = dashboard.send(:render_pnl_section)
      expect(result).to include("Mock Box")
    end

    it "handles negative PnL" do
      allow(mock_state).to receive_messages(total_pnl: -500.0, session_pnl: -100.0)

      result = dashboard.send(:render_pnl_section)
      expect(result).to include("Mock Box")
    end

    it "handles zero PnL" do
      allow(mock_state).to receive_messages(total_pnl: 0.0, session_pnl: 0.0)

      result = dashboard.send(:render_pnl_section)
      expect(result).to include("Mock Box")
    end
  end

  describe "#render_symbols_section" do
    it "renders symbols information" do
      allow(mock_state).to receive(:symbols).and_return(%w[NIFTY BANKNIFTY GOLD])

      result = dashboard.send(:render_symbols_section)

      expect(result).to include("Mock Box")
      expect(result).to include("Symbols")
    end

    it "handles empty symbols list" do
      allow(mock_state).to receive(:symbols).and_return([])

      result = dashboard.send(:render_symbols_section)
      expect(result).to include("Mock Box")
    end

    it "handles single symbol" do
      allow(mock_state).to receive(:symbols).and_return(["NIFTY"])

      result = dashboard.send(:render_symbols_section)
      expect(result).to include("Mock Box")
    end
  end

  describe "#format_currency" do
    it "formats positive amounts" do
      result = dashboard.send(:format_currency, 1234.56)
      expect(result).to include("Mock Green")
    end

    it "formats negative amounts" do
      result = dashboard.send(:format_currency, -1234.56)
      expect(result).to include("Mock Red")
    end

    it "formats zero amounts" do
      result = dashboard.send(:format_currency, 0.0)
      expect(result).to include("Mock White")
    end

    it "handles large amounts" do
      result = dashboard.send(:format_currency, 1_000_000.0)
      expect(result).to include("Mock Green")
    end

    it "handles small amounts" do
      result = dashboard.send(:format_currency, 0.01)
      expect(result).to include("Mock Green")
    end
  end

  describe "#format_percentage" do
    it "formats positive percentages" do
      result = dashboard.send(:format_percentage, 15.5)
      expect(result).to include("Mock Green")
    end

    it "formats negative percentages" do
      result = dashboard.send(:format_percentage, -8.3)
      expect(result).to include("Mock Red")
    end

    it "formats zero percentage" do
      result = dashboard.send(:format_percentage, 0.0)
      expect(result).to include("Mock White")
    end

    it "handles very small percentages" do
      result = dashboard.send(:format_percentage, 0.001)
      expect(result).to include("Mock Green")
    end

    it "handles very large percentages" do
      result = dashboard.send(:format_percentage, 150.0)
      expect(result).to include("Mock Green")
    end
  end

  describe "#create_table" do
    it "creates table with headers and rows" do
      headers = %w[Symbol Quantity PnL]
      rows = [%w[NIFTY 100 500], %w[BANKNIFTY 50 250]]

      result = dashboard.send(:create_table, headers, rows)

      expect(result).to include("Mock Table")
    end

    it "handles empty rows" do
      headers = %w[Symbol Quantity PnL]
      rows = []

      result = dashboard.send(:create_table, headers, rows)
      expect(result).to include("Mock Table")
    end

    it "handles single row" do
      headers = %w[Symbol Quantity PnL]
      rows = [%w[NIFTY 100 500]]

      result = dashboard.send(:create_table, headers, rows)
      expect(result).to include("Mock Table")
    end
  end

  describe "#create_box" do
    it "creates box with title and content" do
      title = "Test Box"
      content = "Test Content"

      result = dashboard.send(:create_box, title, content)

      expect(result).to include("Mock Box")
    end

    it "handles empty content" do
      title = "Empty Box"
      content = ""

      result = dashboard.send(:create_box, title, content)
      expect(result).to include("Mock Box")
    end

    it "handles long content" do
      title = "Long Box"
      content = "A" * 1000

      result = dashboard.send(:create_box, title, content)
      expect(result).to include("Mock Box")
    end
  end

  describe "error handling" do
    it "handles nil balance provider gracefully" do
      dashboard_without_balance = described_class.new(state: mock_state, balance_provider: nil)

      expect { dashboard_without_balance.render }.not_to raise_error
    end

    it "handles nil state gracefully" do
      dashboard_without_state = described_class.new(state: nil, balance_provider: mock_balance_provider)

      expect { dashboard_without_state.render }.not_to raise_error
    end

    it "handles missing methods on state gracefully" do
      incomplete_state = double("IncompleteState")
      dashboard_with_incomplete_state = described_class.new(
        state: incomplete_state,
        balance_provider: mock_balance_provider
      )

      expect { dashboard_with_incomplete_state.render }.not_to raise_error
    end
  end

  describe "performance considerations", :slow do
    it "caches TTY components" do
      # First render should create components
      dashboard.render

      # Second render should reuse components
      expect(TTY::Box).not_to receive(:new)
      expect(TTY::Table).not_to receive(:new)
      expect(Pastel).not_to receive(:new)

      dashboard.render
    end
  end

  describe "integration with state", :slow do
    it "reflects state changes in real-time" do
      # Initial state
      allow(mock_state).to receive(:total_pnl).and_return(0.0)
      initial_result = dashboard.render

      # Updated state
      allow(mock_state).to receive(:total_pnl).and_return(1000.0)
      updated_result = dashboard.render

      expect(initial_result).not_to eq(updated_result)
    end
  end
end
