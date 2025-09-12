# frozen_string_literal: true

require "spec_helper"

RSpec.describe DhanScalper::CLI do
  let(:cli) { described_class.new }
  let(:mock_vdm) do
    double(
      get_balance: 100_000.0,
      get_positions: [],
      get_orders: [],
    )
  end

  before do
    # Mock the App class to avoid actual execution
    stub_const("DhanScalper::App", double)
    allow(DhanScalper::App).to receive(:new).and_return(double)

    # Mock VirtualDataManager
    stub_const("DhanScalper::VirtualDataManager", double)
    allow(DhanScalper::VirtualDataManager).to receive(:new).and_return(mock_vdm)
  end

  describe "#initialize" do
    it "initializes CLI instance" do
      expect(cli).to be_a(described_class)
    end
  end

  describe "#start" do
    it "calls start method on App instance" do
      mock_app = double("App")
      allow(DhanScalper::App).to receive(:new).and_return(mock_app)
      allow(mock_app).to receive(:start)

      cli.start

      expect(mock_app).to have_received(:start)
    end

    it "passes command line arguments to App" do
      mock_app = double("App")
      allow(DhanScalper::App).to receive(:new).and_return(mock_app)
      allow(mock_app).to receive(:start)

      cli.start("--mode", "paper")

      expect(mock_app).to have_received(:start)
    end
  end

  describe "#balance" do
    it "displays current balance" do
      allow(mock_vdm).to receive(:get_balance).and_return(150_000.0)

      result = capture_stdout { cli.balance }

      expect(result).to include("150000.0")
      expect(result).to include("Balance")
    end

    it "displays balance with formatting" do
      allow(mock_vdm).to receive(:get_balance).and_return(123_456.78)

      result = capture_stdout { cli.balance }

      expect(result).to include("123456.78")
    end

    it "handles zero balance" do
      allow(mock_vdm).to receive(:get_balance).and_return(0.0)

      result = capture_stdout { cli.balance }

      expect(result).to include("0.0")
    end

    it "handles negative balance" do
      allow(mock_vdm).to receive(:get_balance).and_return(-5_000.0)

      result = capture_stdout { cli.balance }

      expect(result).to include("-5000.0")
    end
  end

  describe "#positions" do
    context "when no positions exist" do
      before do
        allow(mock_vdm).to receive(:get_positions).and_return([])
      end

      it "displays no positions message" do
        result = capture_stdout { cli.positions }

        expect(result).to include("No open positions")
      end
    end

    context "when positions exist" do
      let(:mock_position) do
        {
          symbol: "NIFTY",
          quantity: 100,
          side: "LONG",
          entry_price: 50.0,
          current_price: 55.0,
          pnl: 500.0,
        }
      end

      before do
        allow(mock_vdm).to receive(:get_positions).and_return([mock_position])
      end

      it "displays position details" do
        result = capture_stdout { cli.positions }

        expect(result).to include("NIFTY")
        expect(result).to include("100")
        expect(result).to include("LONG")
        expect(result).to include("50.0")
        expect(result).to include("55.0")
        expect(result).to include("500.0")
      end

      it "formats position information correctly" do
        result = capture_stdout { cli.positions }

        expect(result).to include("Symbol")
        expect(result).to include("Quantity")
        expect(result).to include("Side")
        expect(result).to include("Entry Price")
        expect(result).to include("Current Price")
        expect(result).to include("PnL")
      end
    end

    context "with multiple positions" do
      let(:mock_positions) do
        [
          {
            symbol: "NIFTY",
            quantity: 100,
            side: "LONG",
            entry_price: 50.0,
            current_price: 55.0,
            pnl: 500.0,
          },
          {
            symbol: "BANKNIFTY",
            quantity: 50,
            side: "SHORT",
            entry_price: 100.0,
            current_price: 95.0,
            pnl: 250.0,
          },
        ]
      end

      before do
        allow(mock_vdm).to receive(:get_positions).and_return(mock_positions)
      end

      it "displays all positions" do
        result = capture_stdout { cli.positions }

        expect(result).to include("NIFTY")
        expect(result).to include("BANKNIFTY")
        expect(result).to include("LONG")
        expect(result).to include("SHORT")
      end
    end
  end

  describe "#orders" do
    context "when no orders exist" do
      before do
        allow(mock_vdm).to receive(:get_orders).and_return([])
      end

      it "displays no orders message" do
        result = capture_stdout { cli.orders }

        expect(result).to include("No orders")
      end
    end

    context "when orders exist" do
      let(:mock_order) do
        {
          order_id: "VIRTUAL_ORDER_1",
          symbol: "NIFTY",
          action: "BUY",
          quantity: 100,
          price: 50.0,
          status: "COMPLETED",
          timestamp: Time.now,
        }
      end

      before do
        allow(mock_vdm).to receive(:get_orders).and_return([mock_order])
      end

      it "displays order details" do
        result = capture_stdout { cli.orders }

        expect(result).to include("VIRTUAL_ORDER_1")
        expect(result).to include("NIFTY")
        expect(result).to include("BUY")
        expect(result).to include("100")
        expect(result).to include("50.0")
        expect(result).to include("COMPLETED")
      end

      it "formats order information correctly" do
        result = capture_stdout { cli.orders }

        expect(result).to include("Order ID")
        expect(result).to include("Symbol")
        expect(result).to include("Action")
        expect(result).to include("Quantity")
        expect(result).to include("Price")
        expect(result).to include("Status")
        expect(result).to include("Timestamp")
      end
    end

    context "with multiple orders" do
      let(:mock_orders) do
        [
          {
            order_id: "VIRTUAL_ORDER_1",
            symbol: "NIFTY",
            action: "BUY",
            quantity: 100,
            price: 50.0,
            status: "COMPLETED",
            timestamp: Time.now,
          },
          {
            order_id: "VIRTUAL_ORDER_2",
            symbol: "NIFTY",
            action: "SELL",
            quantity: 100,
            price: 55.0,
            status: "COMPLETED",
            timestamp: Time.now,
          },
        ]
      end

      before do
        allow(mock_vdm).to receive(:get_orders).and_return(mock_orders)
      end

      it "displays all orders" do
        result = capture_stdout { cli.orders }

        expect(result).to include("VIRTUAL_ORDER_1")
        expect(result).to include("VIRTUAL_ORDER_2")
        expect(result).to include("BUY")
        expect(result).to include("SELL")
      end
    end
  end

  describe "#help" do
    it "displays help information" do
      result = capture_stdout { cli.help }

      expect(result).to include("DhanScalper")
      expect(result).to include("start")
      expect(result).to include("balance")
      expect(result).to include("positions")
      expect(result).to include("orders")
      expect(result).to include("help")
    end

    it "includes command descriptions" do
      result = capture_stdout { cli.help }

      expect(result).to include("Start the scalper")
      expect(result).to include("Show current balance")
      expect(result).to include("Show open positions")
      expect(result).to include("Show order history")
      expect(result).to include("Show this help")
    end

    it "formats help text properly" do
      result = capture_stdout { cli.help }

      expect(result).to include("Commands:")
      expect(result).to include("Options:")
    end
  end

  describe "error handling" do
    it "handles VirtualDataManager errors gracefully" do
      allow(mock_vdm).to receive(:get_balance).and_raise(StandardError, "VDM Error")

      expect { cli.balance }.not_to raise_error
    end

    it "handles missing methods gracefully" do
      incomplete_vdm = double
      allow(DhanScalper::VirtualDataManager).to receive(:new).and_return(incomplete_vdm)

      expect { cli.balance }.not_to raise_error
    end
  end

  describe "output formatting" do
    it "formats currency values consistently" do
      allow(mock_vdm).to receive(:get_balance).and_return(1_234.5678)

      result = capture_stdout { cli.balance }

      expect(result).to include("1234.5678")
    end

    it "handles large numbers" do
      allow(mock_vdm).to receive(:get_balance).and_return(1_000_000.0)

      result = capture_stdout { cli.balance }

      expect(result).to include("1000000.0")
    end

    it "handles small numbers" do
      allow(mock_vdm).to receive(:get_balance).and_return(0.001)

      result = capture_stdout { cli.balance }

      expect(result).to include("0.001")
    end
  end

  describe "command line integration" do
    it "accepts start command" do
      expect { cli.start }.not_to raise_error
    end

    it "accepts balance command" do
      expect { cli.balance }.not_to raise_error
    end

    it "accepts positions command" do
      expect { cli.positions }.not_to raise_error
    end

    it "accepts orders command" do
      expect { cli.orders }.not_to raise_error
    end

    it "accepts help command" do
      expect { cli.help }.not_to raise_error
    end
  end

  describe "Thor integration" do
    it "inherits from Thor" do
      expect(described_class.superclass).to eq(Thor)
    end

    it "defines class options" do
      expect(described_class.class_options).to be_a(Hash)
    end

    it "defines method options" do
      expect(described_class.instance_methods).to include(:start, :balance, :positions, :orders, :help)
    end
  end

  # Helper method to capture stdout
  def capture_stdout
    old_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = old_stdout
  end
end
