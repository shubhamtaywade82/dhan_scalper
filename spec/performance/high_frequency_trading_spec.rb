# frozen_string_literal: true

require "spec_helper"

RSpec.describe "High-Frequency Trading Performance", :performance, :slow do
  let(:config) do
    {
      "global" => {
        "min_profit_target" => 1_000,
        "max_day_loss" => 5_000,
        "decision_interval" => 1, # 1 second for high frequency
        "log_level" => "WARN", # Reduce logging for performance
        "use_multi_timeframe" => true,
        "secondary_timeframe" => 5,
      },
      "paper" => {
        "starting_balance" => 1_000_000,
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
        "FINNIFTY" => {
          "idx_sid" => "26",
          "seg_idx" => "IDX_I",
          "seg_opt" => "NSE_FNO",
          "strike_step" => 50,
          "lot_size" => 50,
          "qty_multiplier" => 1,
          "expiry_wday" => 4,
        },
      },
    }
  end

  let(:paper_app) { DhanScalper::PaperApp.new(config, quiet: true, enhanced: true, timeout_minutes: 5) }

  before do
    setup_performance_mocks
  end

  def setup_performance_mocks
    # Mock WebSocket Manager for high-frequency updates
    @mock_ws_manager = double("WebSocketManager")
    allow(@mock_ws_manager).to receive(:connect)
    allow(@mock_ws_manager).to receive(:connected?).and_return(true)
    allow(@mock_ws_manager).to receive(:on_price_update)
    allow(@mock_ws_manager).to receive(:subscribe_to_instrument)
    allow(@mock_ws_manager).to receive(:unsubscribe_from_instrument)
    allow(paper_app).to receive(:instance_variable_get).with(:@websocket_manager).and_return(@mock_ws_manager)

    # Mock Position Tracker optimized for performance
    @mock_position_tracker = double("PaperPositionTracker")
    @positions = Concurrent::Array.new
    @session_stats = Concurrent::Hash.new({
                                            total_trades: 0,
                                            winning_trades: 0,
                                            losing_trades: 0,
                                            total_pnl: 0.0,
                                            max_profit: 0.0,
                                            max_drawdown: 0.0,
                                          })

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
    end
    allow(@mock_position_tracker).to receive(:get_total_pnl).and_return(@session_stats[:total_pnl])
    allow(paper_app).to receive(:instance_variable_get).with(:@position_tracker).and_return(@mock_position_tracker)

    # Mock Balance Provider optimized for performance
    @mock_balance_provider = double("PaperWallet")
    @available_balance = 1_000_000.0
    @used_balance = 0.0
    @total_balance = 1_000_000.0

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

    # Mock CSV Master with cached data
    @mock_csv_master = double("CsvMaster")
    allow(@mock_csv_master).to receive(:get_expiry_dates).and_return(["2024-12-26"])
    allow(@mock_csv_master).to receive(:get_security_id).and_return("TEST123")
    allow(@mock_csv_master).to receive(:get_lot_size).and_return(75)
    allow(@mock_csv_master).to receive(:get_available_strikes).and_return([25_000, 25_050, 25_100])
    allow(paper_app).to receive(:instance_variable_get).with(:@csv_master).and_return(@mock_csv_master)

    # Mock TickCache with high-performance price simulation
    @price_cache = Concurrent::Hash.new
    allow(DhanScalper::TickCache).to receive(:ltp) do |_segment, security_id|
      @price_cache[security_id] ||= 25_000.0 + rand(-100..100)
    end
    allow(DhanScalper::TickCache).to receive(:get) do |_segment, security_id|
      {
        last_price: @price_cache[security_id] ||= 25_000.0 + rand(-100..100),
        timestamp: Time.now.to_i,
        volume: rand(1_000..10_000),
      }
    end

    # Mock CandleSeries with optimized indicator calculation
    @indicator_cache = Concurrent::Hash.new
    allow(DhanScalper::CandleSeries).to receive(:load_from_dhan_intraday) do |args|
      cache_key = "#{args[:symbol]}_#{args[:interval]}"
      @indicator_cache[cache_key] ||= begin
        mock_series = double("CandleSeries")
        allow(mock_series).to receive(:holy_grail).and_return({
                                                                bias: %i[bullish bearish neutral].sample,
                                                                momentum: %i[strong weak].sample,
                                                                adx: rand(15..40),
                                                                rsi: rand(20..80),
                                                                macd: %i[bullish bearish neutral].sample,
                                                              })
        allow(mock_series).to receive(:supertrend_signal).and_return(%i[bullish bearish none].sample)
        allow(mock_series).to receive(:combined_signal).and_return(%i[bullish bearish none].sample)
        mock_series
      end
    end

    # Mock Option Picker with cached option data
    @option_cache = Concurrent::Hash.new
    @mock_option_picker = double("OptionPicker")
    allow(@mock_option_picker).to receive(:pick_atm_strike) do |spot_price, signal|
      cache_key = "#{spot_price}_#{signal}"
      @option_cache[cache_key] ||= {
        ce: { security_id: "CE_#{spot_price.to_i}", premium: 100.0, strike: spot_price.to_i },
        pe: { security_id: "PE_#{spot_price.to_i}", premium: 80.0, strike: spot_price.to_i },
      }
    end
    allow(paper_app).to receive(:instance_variable_get).with(:@option_pickers).and_return({
                                                                                            "NIFTY" => @mock_option_picker,
                                                                                            "BANKNIFTY" => @mock_option_picker,
                                                                                            "FINNIFTY" => @mock_option_picker,
                                                                                          })

    # Mock Paper Broker with high-performance order execution
    @order_counter = Concurrent::AtomicFixnum.new(0)
    @mock_paper_broker = double("PaperBroker")
    allow(@mock_paper_broker).to receive(:buy_market) do |args|
      order_id = "ORDER_#{@order_counter.increment}"
      {
        order_id: order_id,
        status: "FILLED",
        avg_price: 100.0,
        quantity: args[:quantity],
        timestamp: Time.now,
      }
    end
    allow(@mock_paper_broker).to receive(:sell_market) do |args|
      order_id = "ORDER_#{@order_counter.increment}"
      {
        order_id: order_id,
        status: "FILLED",
        avg_price: 120.0,
        quantity: args[:quantity],
        timestamp: Time.now,
      }
    end
    allow(paper_app).to receive(:instance_variable_get).with(:@paper_broker).and_return(@mock_paper_broker)
  end

  describe "High-Frequency Signal Analysis" do
    it "processes signals at 1-second intervals efficiently" do
      start_time = Time.now
      iterations = 100

      iterations.times do |_i|
        paper_app.analyze_and_trade
        sleep(0.01) # Simulate 1-second interval
      end

      duration = Time.now - start_time
      expect(duration).to be < 2.0 # Should complete within 2 seconds
      expect(duration / iterations).to be < 0.02 # Each iteration should take less than 20ms
    end

    it "handles concurrent signal processing" do
      threads = []
      results = []

      # Simulate 10 concurrent trading sessions
      10.times do |_i|
        threads << Thread.new do
          session_results = []
          50.times do
            start_time = Time.now
            paper_app.analyze_and_trade
            duration = Time.now - start_time
            session_results << duration
          end
          results << session_results
        end
      end

      threads.each(&:join)

      # Verify all sessions completed successfully
      expect(results.length).to eq(10)
      expect(results.all? { |r| r.length == 50 }).to be true

      # Verify performance is maintained under concurrency
      avg_duration = results.flatten.sum / results.flatten.length
      expect(avg_duration).to be < 0.05 # Average should be less than 50ms
    end

    it "maintains performance with large position counts" do
      # Create many positions to test performance under load
      100.times do |i|
        @positions << {
          position_id: "POS_#{i}",
          symbol: "NIFTY",
          security_id: "CE_#{25_000 + i}",
          status: "open",
          pnl: rand(-1_000..1_000),
          entry_time: Time.now,
        }
      end

      start_time = Time.now
      100.times do
        paper_app.analyze_and_trade
      end
      duration = Time.now - start_time

      expect(duration).to be < 5.0 # Should still complete within 5 seconds
    end
  end

  describe "Memory Management" do
    it "maintains stable memory usage during long sessions" do
      initial_memory = `ps -o rss= -p #{Process.pid}`.to_i

      # Simulate 1-hour session (3600 iterations at 1-second intervals)
      3_600.times do |i|
        paper_app.analyze_and_trade

        # Simulate memory cleanup every 100 iterations
        next unless i % 100 == 0

        @positions = @positions.last(50) # Keep only recent positions
        @price_cache.clear if @price_cache.size > 1_000
        @indicator_cache.clear if @indicator_cache.size > 100
      end

      final_memory = `ps -o rss= -p #{Process.pid}`.to_i
      memory_increase = final_memory - initial_memory

      # Memory increase should be reasonable even for long sessions
      expect(memory_increase).to be < 100_000 # Less than 100MB
    end

    it "handles memory pressure gracefully" do
      # Simulate memory pressure by creating many objects
      1_000.times do |i|
        @positions << {
          position_id: "POS_#{i}",
          symbol: "NIFTY",
          security_id: "CE_#{25_000 + i}",
          status: "open",
          pnl: rand(-1_000..1_000),
          entry_time: Time.now,
          large_data: "x" * 1_000, # Add some memory pressure
        }
      end

      # System should still function under memory pressure
      start_time = Time.now
      100.times do
        paper_app.analyze_and_trade
      end
      duration = Time.now - start_time

      expect(duration).to be < 10.0 # Should still complete within 10 seconds
    end
  end

  describe "CPU Performance" do
    it "maintains low CPU usage during continuous operation" do
      # Monitor CPU usage during operation
      cpu_before = get_cpu_usage

      start_time = Time.now
      1_000.times do |_i|
        paper_app.analyze_and_trade
        sleep(0.001) # 1ms sleep to prevent 100% CPU usage
      end
      duration = Time.now - start_time

      cpu_after = get_cpu_usage
      cpu_increase = cpu_after - cpu_before

      # CPU increase should be reasonable
      expect(cpu_increase).to be < 50 # Less than 50% increase
      expect(duration).to be < 5.0 # Should complete within 5 seconds
    end

    it "handles CPU-intensive calculations efficiently" do
      # Simulate CPU-intensive scenario with complex indicators
      allow(DhanScalper::CandleSeries).to receive(:load_from_dhan_intraday) do |_args|
        # Simulate complex calculation
        sleep(0.001) # 1ms delay to simulate complex calculation
        mock_series = double("CandleSeries")
        allow(mock_series).to receive(:holy_grail).and_return({
                                                                bias: :bullish,
                                                                momentum: :strong,
                                                                adx: 30.0,
                                                                rsi: 65.0,
                                                                macd: :bullish,
                                                              })
        allow(mock_series).to receive(:supertrend_signal).and_return(:bullish)
        allow(mock_series).to receive(:combined_signal).and_return(:bullish)
        mock_series
      end

      start_time = Time.now
      100.times do
        paper_app.analyze_and_trade
      end
      duration = Time.now - start_time

      expect(duration).to be < 2.0 # Should still complete within 2 seconds
    end
  end

  describe "Network Performance" do
    it "handles simulated network latency efficiently" do
      # Simulate network latency
      allow(DhanScalper::TickCache).to receive(:ltp) do |_segment, security_id|
        sleep(0.005) # 5ms network delay
        @price_cache[security_id] ||= 25_000.0 + rand(-100..100)
      end

      start_time = Time.now
      100.times do
        paper_app.analyze_and_trade
      end
      duration = Time.now - start_time

      expect(duration).to be < 3.0 # Should complete within 3 seconds despite latency
    end

    it "handles network failures gracefully" do
      # Simulate intermittent network failures
      call_count = 0
      allow(DhanScalper::TickCache).to receive(:ltp) do |_segment, security_id|
        call_count += 1
        raise StandardError, "Network timeout" if call_count % 10 == 0

        @price_cache[security_id] ||= 25_000.0 + rand(-100..100)
      end

      # Should handle network failures gracefully
      expect do
        100.times { paper_app.analyze_and_trade }
      end.not_to raise_error
    end
  end

  describe "Scalability" do
    it "scales with multiple symbols" do
      symbols = %w[NIFTY BANKNIFTY FINNIFTY]

      start_time = Time.now
      100.times do
        symbols.each do |_symbol|
          paper_app.analyze_and_trade
        end
      end
      duration = Time.now - start_time

      # Should scale linearly with number of symbols
      expect(duration).to be < 5.0 # Should complete within 5 seconds
    end

    it "scales with increased trading frequency" do
      frequencies = [1, 2, 5, 10] # trades per second

      frequencies.each do |freq|
        start_time = Time.now
        (100 * freq).times do
          paper_app.analyze_and_trade
        end
        duration = Time.now - start_time

        # Should scale reasonably with frequency
        expect(duration).to be < 10.0 # Should complete within 10 seconds
      end
    end
  end

  private

  def get_cpu_usage
    # Get CPU usage percentage
    `ps -o pcpu= -p #{Process.pid}`.to_f
  end
end
