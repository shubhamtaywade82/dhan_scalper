# frozen_string_literal: true

require "concurrent"
require "timeout"

module AdvancedTestHelpers
  # Advanced mock factories for complex scenarios
  class MockFactory
    def self.create_realistic_market_data(symbols: ["NIFTY"], periods: 200)
      symbols.each_with_object({}) do |symbol, data|
        base_price = case symbol
                     when "NIFTY" then 25_000
                     when "BANKNIFTY" then 50_000
                     when "FINNIFTY" then 20_000
                     else 25_000
                     end

        data[symbol] = {
          current_price: base_price,
          price_history: generate_price_history(base_price, periods),
          trend: %i[bullish bearish neutral].sample,
          volatility: rand(0.1..0.3),
          volume: rand(10_000..100_000),
        }
      end
    end

    def self.create_realistic_positions(count: 10, symbols: ["NIFTY"])
      (1..count).map do |i|
        symbol = symbols.sample
        {
          position_id: "POS_#{i}",
          symbol: symbol,
          security_id: "#{symbol}_#{25_000 + (i * 50)}",
          status: %w[open closed].sample,
          side: %w[BUY SELL].sample,
          quantity: case symbol
                    when "NIFTY" then 75
                    when "BANKNIFTY" then 25
                    when "FINNIFTY" then 50
                    else 75
                    end,
          entry_price: rand(50..200),
          current_price: rand(50..200),
          pnl: rand(-2_000..2_000),
          entry_time: Time.now - rand(0..3_600),
          exit_time: rand < 0.5 ? Time.now - rand(0..1_800) : nil,
          exit_reason: %w[profit_target stop_loss timeout].sample,
        }
      end
    end

    def self.create_realistic_orders(count: 20)
      (1..count).map do |i|
        {
          order_id: "ORDER_#{i}",
          symbol: %w[NIFTY BANKNIFTY FINNIFTY].sample,
          security_id: "SEC_#{i}",
          side: %w[BUY SELL].sample,
          quantity: rand(25..100),
          price: rand(50..200),
          status: %w[PENDING FILLED CANCELLED REJECTED].sample,
          timestamp: Time.now - rand(0..3_600),
          avg_price: rand(50..200),
          filled_quantity: rand(0..100),
        }
      end
    end

    def self.create_realistic_session_stats
      {
        start_time: Time.now - rand(3_600..7_200),
        end_time: Time.now,
        total_trades: rand(10..100),
        winning_trades: rand(5..50),
        losing_trades: rand(5..50),
        win_rate: rand(30.0..80.0),
        total_pnl: rand(-5_000..10_000),
        max_profit: rand(1_000..5_000),
        max_drawdown: rand(-5_000..-1_000),
        current_drawdown: rand(-2_000..0),
        avg_trade_duration: rand(300..1_800),
        max_concurrent_positions: rand(1..10),
      }
    end

    def self.generate_price_history(base_price, periods)
      prices = [base_price]
      trend = rand(-0.01..0.01) # Small trend component
      volatility = rand(0.05..0.15)

      (1...periods).each do |_i|
        # Random walk with trend
        change = trend + ((rand - 0.5) * volatility)
        new_price = prices.last * (1 + change)
        prices << new_price.round(2)
      end

      prices
    end
  end

  # Performance testing utilities
  class PerformanceMonitor
    def initialize
      @start_time = nil
      @end_time = nil
      @memory_samples = []
      @cpu_samples = []
    end

    def start
      @start_time = Time.now
      @memory_samples << get_memory_usage
      @cpu_samples << get_cpu_usage
    end

    def stop
      @end_time = Time.now
      @memory_samples << get_memory_usage
      @cpu_samples << get_cpu_usage
    end

    def duration
      return nil unless @start_time && @end_time

      @end_time - @start_time
    end

    def memory_usage
      return nil if @memory_samples.empty?

      @memory_samples.max - @memory_samples.min
    end

    def cpu_usage
      return nil if @cpu_samples.empty?

      @cpu_samples.max - @cpu_samples.min
    end

    def throughput(operations)
      return nil unless duration

      operations / duration
    end

    def sample_performance
      @memory_samples << get_memory_usage
      @cpu_samples << get_cpu_usage
    end

    private

    def get_memory_usage
      `ps -o rss= -p #{Process.pid}`.to_i
    end

    def get_cpu_usage
      `ps -o pcpu= -p #{Process.pid}`.to_f
    end
  end

  # Concurrent testing utilities
  class ConcurrentTestRunner
    def self.run_concurrent_operations(operations, thread_count: 10)
      threads = []
      results = []
      mutex = Mutex.new

      thread_count.times do |i|
        threads << Thread.new do
          thread_results = []
          operations_per_thread = operations / thread_count

          operations_per_thread.times do |j|
            start_time = Time.now
            result = yield(i, j)
            duration = Time.now - start_time

            thread_results << {
              thread_id: i,
              operation_id: j,
              result: result,
              duration: duration,
            }
          end

          mutex.synchronize do
            results.concat(thread_results)
          end
        end
      end

      threads.each(&:join)
      results
    end

    def self.run_with_timeout(operation, timeout_seconds: 30)
      Timeout.timeout(timeout_seconds) do
        operation.call
      end
    rescue Timeout::Error
      raise "Operation timed out after #{timeout_seconds} seconds"
    end
  end

  # Market simulation utilities
  class MarketSimulator
    def initialize(symbols: ["NIFTY"], volatility: 0.15)
      @symbols = symbols
      @volatility = volatility
      @prices = {}
      @trends = {}
      @volumes = {}

      initialize_market_data
    end

    def simulate_price_movement(symbol, time_step: 1)
      return @prices[symbol] unless @prices[symbol]

      current_price = @prices[symbol]
      trend = @trends[symbol] || 0.0
      volatility = @volatility

      # Random walk with trend
      change = trend + ((rand - 0.5) * volatility * 0.1)
      new_price = current_price * (1 + change)

      @prices[symbol] = new_price.round(2)
      @volumes[symbol] = rand(1_000..10_000)

      new_price
    end

    def set_trend(symbol, trend)
      @trends[symbol] = case trend
                        when :bullish then 0.001
                        when :bearish then -0.001
                        when :neutral then 0.0
                        else 0.0
                        end
    end

    def get_current_price(symbol)
      @prices[symbol]
    end

    def get_volume(symbol)
      @volumes[symbol]
    end

    def simulate_market_crash(symbols: @symbols)
      symbols.each do |symbol|
        @prices[symbol] *= 0.9 # 10% drop
        set_trend(symbol, :bearish)
      end
    end

    def simulate_market_rally(symbols: @symbols)
      symbols.each do |symbol|
        @prices[symbol] *= 1.1 # 10% rise
        set_trend(symbol, :bullish)
      end
    end

    private

    def initialize_market_data
      @symbols.each do |symbol|
        base_price = case symbol
                     when "NIFTY" then 25_000
                     when "BANKNIFTY" then 50_000
                     when "FINNIFTY" then 20_000
                     else 25_000
                     end

        @prices[symbol] = base_price
        @trends[symbol] = 0.0
        @volumes[symbol] = rand(1_000..10_000)
      end
    end
  end

  # Error simulation utilities
  class ErrorSimulator
    def self.simulate_network_failures(probability: 0.1)
      -> { rand < probability ? raise(StandardError, "Network timeout") : nil }
    end

    def self.simulate_api_failures(probability: 0.05)
      -> { rand < probability ? raise(StandardError, "API rate limit exceeded") : nil }
    end

    def self.simulate_data_corruption(probability: 0.02)
      -> { rand < probability ? nil : "valid_data" }
    end

    def self.simulate_memory_pressure
      -> { "x" * 1_000_000 } # Allocate 1MB
    end
  end

  # Test data generators
  class TestDataGenerator
    def self.generate_candle_series(symbol: "NIFTY", count: 200, trend: :neutral)
      base_price = case symbol
                   when "NIFTY" then 25_000
                   when "BANKNIFTY" then 50_000
                   when "FINNIFTY" then 20_000
                   else 25_000
                   end

      trend_multiplier = case trend
                         when :bullish then 1.001
                         when :bearish then 0.999
                         else 1.0
                         end

      candles = []
      current_price = base_price

      count.times do |i|
        # Generate realistic OHLC data
        open = current_price
        high = open + rand(0..50)
        low = open - rand(0..50)
        close = low + rand(0..(high - low))
        volume = rand(1_000..10_000)

        candles << DhanScalper::Candle.new(
          ts: Time.now - ((count - i) * 60),
          open: open,
          high: high,
          low: low,
          close: close,
          volume: volume,
        )

        current_price = close * trend_multiplier
      end

      candles
    end

    def self.generate_tick_data(symbol: "NIFTY", count: 1_000)
      base_price = case symbol
                   when "NIFTY" then 25_000
                   when "BANKNIFTY" then 50_000
                   when "FINNIFTY" then 20_000
                   else 25_000
                   end

      (1..count).map do |i|
        {
          security_id: case symbol
                       when "NIFTY" then "13"
                       when "BANKNIFTY" then "25"
                       when "FINNIFTY" then "26"
                       else "13"
                       end,
          last_price: base_price + rand(-100..100),
          timestamp: Time.now - (count - i),
          volume: rand(1_000..10_000),
          high: base_price + rand(0..100),
          low: base_price - rand(0..100),
          open: base_price + rand(-50..50),
        }
      end
    end
  end

  # Assertion helpers
  class AssertionHelpers
    def self.assert_performance_within_limits(duration, max_duration)
      expect(duration).to be < max_duration
    end

    def self.assert_memory_usage_reasonable(initial_memory, final_memory, max_increase_mb: 100)
      increase_kb = final_memory - initial_memory
      increase_mb = increase_kb / 1_024.0
      expect(increase_mb).to be < max_increase_mb
    end

    def self.assert_concurrent_safety(results)
      # Check that all operations completed successfully
      expect(results.all? { |r| r[:result] }).to be true

      # Check that no race conditions occurred
      expect(results.length).to be > 0
    end

    def self.assert_error_handling(operation, expected_errors: [])
      expect { operation.call }.not_to raise_error(*expected_errors)
    end
  end

  # Benchmark utilities
  class Benchmark
    def self.measure(operation, iterations: 1)
      durations = []

      iterations.times do
        start_time = Time.now
        operation.call
        durations << (Time.now - start_time)
      end

      {
        min: durations.min,
        max: durations.max,
        avg: durations.sum / durations.length,
        total: durations.sum,
      }
    end

    def self.compare(operations)
      results = {}

      operations.each do |name, operation|
        results[name] = measure(operation)
      end

      results
    end
  end
end

# Include advanced test helpers in RSpec
RSpec.configure do |config|
  config.include AdvancedTestHelpers
  config.include AdvancedTestHelpers::MockFactory
  config.include AdvancedTestHelpers::PerformanceMonitor
  config.include AdvancedTestHelpers::ConcurrentTestRunner
  config.include AdvancedTestHelpers::MarketSimulator
  config.include AdvancedTestHelpers::ErrorSimulator
  config.include AdvancedTestHelpers::TestDataGenerator
  config.include AdvancedTestHelpers::AssertionHelpers
  config.include AdvancedTestHelpers::Benchmark
end
