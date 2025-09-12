# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Complete Trading Session End-to-End", :e2e, :slow do
  let(:config) do
    {
      "global" => {
        "min_profit_target" => 2_000,
        "max_day_loss" => 8_000,
        "decision_interval" => 3,
        "log_level" => "INFO",
        "use_multi_timeframe" => true,
        "secondary_timeframe" => 5,
      },
      "paper" => {
        "starting_balance" => 500_000,
      },
      "SYMBOLS" => {
        "NIFTY" => {
          "idx_sid" => "13",
          "seg_idx" => "IDX_I",
          "seg_opt" => "NSE_FNO",
          "strike_step" => 50,
          "lot_size" => 75,
          "qty_multiplier" => 1,
          "expiry_wday" => 4,
        },
        "BANKNIFTY" => {
          "idx_sid" => "25",
          "seg_idx" => "IDX_I",
          "seg_opt" => "NSE_FNO",
          "strike_step" => 100,
          "lot_size" => 25,
          "qty_multiplier" => 1,
          "expiry_wday" => 4,
        },
      },
    }
  end

  let(:paper_app) { DhanScalper::PaperApp.new(config, quiet: true, enhanced: true, timeout_minutes: 3) }

  before do
    setup_e2e_environment
  end

  def setup_e2e_environment
    # Create realistic market data simulation
    @market_data = {
      "NIFTY" => {
        current_price: 25_000.0,
        price_history: [],
        trend: :bullish,
        volatility: 0.15,
      },
      "BANKNIFTY" => {
        current_price: 50_000.0,
        price_history: [],
        trend: :bearish,
        volatility: 0.18,
      },
    }

    # Initialize realistic position tracking
    @positions = []
    @orders = []
    @session_stats = {
      start_time: Time.now,
      total_trades: 0,
      winning_trades: 0,
      losing_trades: 0,
      total_pnl: 0.0,
      max_profit: 0.0,
      max_drawdown: 0.0,
      current_drawdown: 0.0,
    }

    setup_realistic_mocks
  end

  def setup_realistic_mocks
    # Mock WebSocket Manager with realistic behavior
    @mock_ws_manager = double("WebSocketManager")
    allow(@mock_ws_manager).to receive(:connect)
    allow(@mock_ws_manager).to receive(:connected?).and_return(true)
    allow(@mock_ws_manager).to receive(:on_price_update) do |&block|
      @price_update_callback = block
    end
    allow(@mock_ws_manager).to receive(:subscribe_to_instrument)
    allow(@mock_ws_manager).to receive(:unsubscribe_from_instrument)
    allow(paper_app).to receive(:instance_variable_get).with(:@websocket_manager).and_return(@mock_ws_manager)

    # Mock Position Tracker with realistic state management
    @mock_position_tracker = double("PaperPositionTracker")
    allow(@mock_position_tracker).to receive(:setup_websocket_handlers)
    allow(@mock_position_tracker).to receive(:track_underlying)
    allow(@mock_position_tracker).to receive(:get_open_positions).and_return(@positions.select { |p|
      p[:status] == "open"
    })
    allow(@mock_position_tracker).to receive(:get_positions_summary) do
      open_positions = @positions.select { |p| p[:status] == "open" }
      closed_positions = @positions.select { |p| p[:status] == "closed" }
      total_pnl = @positions.sum { |p| p[:pnl] || 0 }

      {
        total_positions: @positions.length,
        open_positions: open_positions.length,
        closed_positions: closed_positions.length,
        total_pnl: total_pnl,
        session_pnl: @session_stats[:total_pnl],
      }
    end
    allow(@mock_position_tracker).to receive(:get_session_stats).and_return(@session_stats)
    allow(@mock_position_tracker).to receive(:add_position) do |position_data|
      position = position_data.merge(
        status: "open",
        pnl: 0.0,
        entry_time: Time.now,
        position_id: "POS_#{@positions.length + 1}",
      )
      @positions << position
      update_session_stats(position)
    end
    allow(@mock_position_tracker).to receive(:get_total_pnl).and_return(@session_stats[:total_pnl])
    allow(paper_app).to receive(:instance_variable_get).with(:@position_tracker).and_return(@mock_position_tracker)

    # Mock Balance Provider with realistic balance tracking
    @mock_balance_provider = double("PaperWallet")
    @available_balance = 500_000.0
    @used_balance = 0.0
    @total_balance = 500_000.0

    allow(@mock_balance_provider).to receive(:available_balance).and_return(@available_balance)
    allow(@mock_balance_provider).to receive(:total_balance).and_return(@total_balance)
    allow(@mock_balance_provider).to receive(:used_balance).and_return(@used_balance)
    allow(@mock_balance_provider).to receive(:update_balance) do |amount, type:|
      case type
      when :debit
        @available_balance -= amount
        @used_balance += amount
      when :credit
        @available_balance += amount
        @used_balance -= amount
      end
      @total_balance = @available_balance + @used_balance
    end
    allow(paper_app).to receive(:instance_variable_get).with(:@balance_provider).and_return(@mock_balance_provider)

    # Mock CSV Master with realistic data
    @mock_csv_master = double("CsvMaster")
    allow(@mock_csv_master).to receive(:get_expiry_dates).and_return(%w[2024-12-26 2025-01-02 2025-01-09])
    allow(@mock_csv_master).to receive(:get_security_id) do |_symbol, expiry, strike, option_type|
      "#{option_type}_#{strike}_#{expiry.delete("-")}"
    end
    allow(@mock_csv_master).to receive(:get_lot_size) do |security_id|
      security_id.include?("NIFTY") ? 75 : 25
    end
    allow(@mock_csv_master).to receive(:get_available_strikes) do |symbol, _expiry|
      case symbol
      when "NIFTY"
        base = 25_000
        (base - 500..base + 500).step(50).to_a
      when "BANKNIFTY"
        base = 50_000
        (base - 1_000..base + 1_000).step(100).to_a
      end
    end
    allow(paper_app).to receive(:instance_variable_get).with(:@csv_master).and_return(@mock_csv_master)

    # Mock TickCache with realistic price simulation
    allow(DhanScalper::TickCache).to receive(:ltp) do |_segment, security_id|
      case security_id
      when "13" then simulate_price_movement("NIFTY")
      when "25" then simulate_price_movement("BANKNIFTY")
      else 100.0
      end
    end
    allow(DhanScalper::TickCache).to receive(:get) do |_segment, security_id|
      {
        last_price: simulate_price_movement(security_id == "13" ? "NIFTY" : "BANKNIFTY"),
        timestamp: Time.now.to_i,
        volume: rand(1_000..10_000),
      }
    end

    # Mock CandleSeries with realistic indicator simulation
    allow(DhanScalper::CandleSeries).to receive(:load_from_dhan_intraday) do |args|
      symbol = args[:symbol] || "NIFTY"
      mock_series = double("CandleSeries")

      # Simulate realistic indicator values
      indicators = simulate_indicators(symbol)

      allow(mock_series).to receive(:holy_grail).and_return(indicators[:holy_grail])
      allow(mock_series).to receive(:supertrend_signal).and_return(indicators[:supertrend])
      allow(mock_series).to receive(:combined_signal).and_return(indicators[:combined])
      mock_series
    end

    # Mock Option Picker with realistic option pricing
    @mock_option_picker = double("OptionPicker")
    allow(@mock_option_picker).to receive(:pick_atm_strike) do |spot_price, signal|
      strike = calculate_atm_strike(spot_price, signal)
      volatility = @market_data[spot_price > 30_000 ? "BANKNIFTY" : "NIFTY"][:volatility]

      {
        ce: {
          security_id: "CE_#{strike}_#{Time.now.strftime("%Y%m%d")}",
          premium: calculate_option_premium(spot_price, strike, "CE", volatility),
          strike: strike,
        },
        pe: {
          security_id: "PE_#{strike}_#{Time.now.strftime("%Y%m%d")}",
          premium: calculate_option_premium(spot_price, strike, "PE", volatility),
          strike: strike,
        },
      }
    end
    allow(paper_app).to receive(:instance_variable_get).with(:@option_pickers).and_return({
                                                                                            "NIFTY" => @mock_option_picker,
                                                                                            "BANKNIFTY" => @mock_option_picker,
                                                                                          })

    # Mock Paper Broker with realistic order execution
    @order_counter = 0
    @mock_paper_broker = double("PaperBroker")
    allow(@mock_paper_broker).to receive(:buy_market) do |args|
      @order_counter += 1
      order = {
        order_id: "ORDER_#{@order_counter}",
        status: "FILLED",
        avg_price: args[:price] || 100.0,
        quantity: args[:quantity],
        timestamp: Time.now,
        side: "BUY",
      }
      @orders << order
      order
    end
    allow(@mock_paper_broker).to receive(:sell_market) do |args|
      @order_counter += 1
      order = {
        order_id: "ORDER_#{@order_counter}",
        status: "FILLED",
        avg_price: args[:price] || 120.0,
        quantity: args[:quantity],
        timestamp: Time.now,
        side: "SELL",
      }
      @orders << order
      order
    end
    allow(paper_app).to receive(:instance_variable_get).with(:@paper_broker).and_return(@mock_paper_broker)
  end

  def simulate_price_movement(symbol)
    data = @market_data[symbol]
    return data[:current_price] unless data

    # Simulate realistic price movement
    change_pct = (rand - 0.5) * data[:volatility] * 0.1 # Small random change
    new_price = data[:current_price] * (1 + change_pct)

    # Apply trend bias
    case data[:trend]
    when :bullish
      new_price *= 1.001
    when :bearish
      new_price *= 0.999
    end

    data[:current_price] = new_price.round(2)
    data[:price_history] << { price: new_price, timestamp: Time.now }

    # Keep only last 100 price points
    data[:price_history] = data[:price_history].last(100)

    new_price
  end

  def simulate_indicators(symbol)
    data = @market_data[symbol]
    data[:current_price]

    # Simulate realistic indicator values based on trend
    case data[:trend]
    when :bullish
      {
        holy_grail: {
          bias: :bullish,
          momentum: :strong,
          adx: rand(25..40),
          rsi: rand(60..80),
          macd: :bullish,
        },
        supertrend: :bullish,
        combined: :bullish,
      }
    when :bearish
      {
        holy_grail: {
          bias: :bearish,
          momentum: :strong,
          adx: rand(25..40),
          rsi: rand(20..40),
          macd: :bearish,
        },
        supertrend: :bearish,
        combined: :bearish,
      }
    else
      {
        holy_grail: {
          bias: :neutral,
          momentum: :weak,
          adx: rand(15..25),
          rsi: rand(40..60),
          macd: :neutral,
        },
        supertrend: :none,
        combined: :none,
      }
    end
  end

  def calculate_atm_strike(spot_price, signal)
    case signal
    when :bullish
      # Slightly ITM for bullish
      ((spot_price / 50).round * 50) - 50
    when :bearish
      # Slightly ITM for bearish
      ((spot_price / 50).round * 50) + 50
    else
      # ATM
      (spot_price / 50).round * 50
    end
  end

  def calculate_option_premium(spot_price, strike, option_type, volatility)
    # Simplified Black-Scholes approximation

    time_value = 50.0 # Base time value
    intrinsic_value = [option_type == "CE" ? spot_price - strike : strike - spot_price, 0].max

    base_premium = intrinsic_value + time_value
    volatility_adjustment = volatility * 1_000

    (base_premium + volatility_adjustment).round(2)
  end

  def update_session_stats(position)
    @session_stats[:total_trades] += 1
    if position[:pnl] > 0
      @session_stats[:winning_trades] += 1
    elsif position[:pnl] < 0
      @session_stats[:losing_trades] += 1
    end

    @session_stats[:total_pnl] += position[:pnl] || 0
    @session_stats[:max_profit] = [@session_stats[:max_profit], @session_stats[:total_pnl]].max
    @session_stats[:max_drawdown] =
      [@session_stats[:max_drawdown], @session_stats[:total_pnl] - @session_stats[:max_profit]].min
  end

  describe "Complete Trading Session Simulation" do
    it "executes a realistic trading session with multiple scenarios" do
      # Start the session
      expect(paper_app).to receive(:initialize_components)
      expect(paper_app).to receive(:start_websocket_connection)
      expect(paper_app).to receive(:cleanup_and_report)

      # Mock the main trading loop with realistic behavior
      allow(paper_app).to receive(:main_trading_loop) do
        # Simulate 20 trading cycles with different market conditions
        20.times do |cycle|
          # Change market trend every 5 cycles
          if cycle % 5 == 0
            @market_data["NIFTY"][:trend] = cycle < 10 ? :bullish : :bearish
            @market_data["BANKNIFTY"][:trend] = cycle < 10 ? :bearish : :bullish
          end

          # Execute trading analysis
          paper_app.analyze_and_trade

          # Simulate position management
          manage_positions

          # Simulate decision interval
          sleep(0.05)
        end
      end

      # Start the session
      paper_app.start

      # Verify session results
      expect(@session_stats[:total_trades]).to be > 0
      expect(@positions.length).to be > 0
      expect(@orders.length).to be > 0
    end

    it "handles complex market scenarios" do
      # Test scenario: Volatile market with trend changes
      @market_data["NIFTY"][:volatility] = 0.25
      @market_data["BANKNIFTY"][:volatility] = 0.30

      # Simulate 50 cycles with frequent trend changes
      50.times do |_cycle|
        # Random trend changes
        if rand < 0.2 # 20% chance of trend change
          @market_data["NIFTY"][:trend] = %i[bullish bearish neutral].sample
          @market_data["BANKNIFTY"][:trend] = %i[bullish bearish neutral].sample
        end

        paper_app.analyze_and_trade
        manage_positions
      end

      # Verify system handled volatility
      expect(@session_stats[:total_trades]).to be > 0
      expect(@positions.length).to be > 0
    end

    it "manages risk effectively across multiple positions" do
      # Create multiple positions to test risk management
      @positions = [
        { symbol: "NIFTY", security_id: "CE_25000", pnl: 1_000.0, status: "open" },
        { symbol: "BANKNIFTY", security_id: "PE_50000", pnl: -500.0, status: "open" },
        { symbol: "NIFTY", security_id: "CE_25100", pnl: -2_000.0, status: "open" },
      ]

      @session_stats[:total_pnl] = -1_500.0

      # Test risk limit check
      result = paper_app.check_risk_limits
      expect(result).to be true # Should still be within limits

      # Test breach scenario
      @session_stats[:total_pnl] = -9_000.0
      result = paper_app.check_risk_limits
      expect(result).to be false # Should breach limits
    end

    it "generates comprehensive session reports" do
      # Set up realistic session data
      @session_stats = {
        start_time: Time.now - 3_600, # 1 hour ago
        total_trades: 25,
        winning_trades: 15,
        losing_trades: 10,
        total_pnl: 3_500.0,
        max_profit: 5_000.0,
        max_drawdown: -1_500.0,
        current_drawdown: -500.0,
      }

      @positions = [
        { symbol: "NIFTY", status: "open", pnl: 500.0, entry_time: Time.now - 1_800 },
        { symbol: "BANKNIFTY", status: "closed", pnl: 3_000.0, entry_time: Time.now - 3_600, exit_time: Time.now - 1_800 },
      ]

      # Test report generation
      expect(paper_app).to receive(:puts).with(/SESSION REPORT/)
      expect(paper_app).to receive(:puts).with(/Total Trades: 25/)
      expect(paper_app).to receive(:puts).with(/Win Rate: 60.0%/)
      expect(paper_app).to receive(:puts).with(/Total P&L: ₹3500.00/)
      expect(paper_app).to receive(:puts).with(/Max Profit: ₹5000.00/)
      expect(paper_app).to receive(:puts).with(/Max Drawdown: ₹-1500.00/)

      paper_app.generate_session_report
    end
  end

  describe "Performance and Scalability" do
    it "handles high-frequency trading efficiently" do
      start_time = Time.now

      # Simulate 1000 rapid trading cycles
      1_000.times do
        paper_app.analyze_and_trade
        manage_positions
      end

      duration = Time.now - start_time
      expect(duration).to be < 5.0 # Should complete within 5 seconds
    end

    it "maintains system stability during extended sessions" do
      initial_memory = `ps -o rss= -p #{Process.pid}`.to_i

      # Simulate 2-hour session (7200 cycles at 1-second intervals)
      7_200.times do |cycle|
        paper_app.analyze_and_trade
        manage_positions

        # Simulate memory cleanup every 100 cycles
        if cycle % 100 == 0
          @positions = @positions.last(50) # Keep only recent positions
          @orders = @orders.last(100) # Keep only recent orders
        end
      end

      final_memory = `ps -o rss= -p #{Process.pid}`.to_i
      memory_increase = final_memory - initial_memory

      # Memory increase should be reasonable even for long sessions
      expect(memory_increase).to be < 50_000 # Less than 50MB
    end
  end

  private

  def manage_positions
    # Simulate position management logic
    @positions.each do |position|
      next unless position[:status] == "open"

      # Simulate P&L calculation
      current_price = simulate_price_movement(position[:symbol])
      entry_price = position[:entry_price] || 100.0
      position[:pnl] = (current_price - entry_price) * (position[:quantity] || 75)

      # Simulate position closing based on P&L
      next unless position[:pnl] > 2_000 || position[:pnl] < -1_000

      position[:status] = "closed"
      position[:exit_time] = Time.now
      position[:exit_reason] = position[:pnl] > 0 ? "profit_target" : "stop_loss"
    end
  end
end
