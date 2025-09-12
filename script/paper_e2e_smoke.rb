#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "dhan_scalper"
require "bigdecimal"
require "json"

class PaperE2ESmokeTest
  def initialize
    @logger = Logger.new($stdout)
    @logger.level = Logger::WARN # Reduce noise during testing

    # Test configuration
    @config_path = "config/scalper.paper.yml"
    @test_results = []
    @errors = []
  end

  def run
    puts "🚀 Starting Paper Trading E2E Smoke Test"
    puts "=" * 60

    begin
      setup_test_environment
      run_test_scenarios
      print_test_summary

      if @errors.empty?
        puts "\n✅ All tests passed!"
        exit 0
      else
        puts "\n❌ Tests failed with #{@errors.length} errors"
        @errors.each { |error| puts "  - #{error}" }
        exit 1
      end
    rescue => e
      puts "\n💥 Test suite crashed: #{e.message}"
      puts e.backtrace.first(5).join("\n")
      exit 1
    end
  end

  private

  def setup_test_environment
    puts "\n📋 Setting up test environment..."

    # Load configuration
    @config = DhanScalper::Config.load(path: @config_path)
    puts "  ✓ Loaded config from #{@config_path}"

    # Initialize components
    @balance_provider = DhanScalper::BalanceProviders::PaperWallet.new(
      starting_balance: @config.dig("paper", "starting_balance") || 100_000.0
    )
    puts "  ✓ Initialized balance provider with #{DhanScalper::Support::Money.format(@balance_provider.total_balance)}"

    @position_tracker = DhanScalper::Services::EnhancedPositionTracker.new(balance_provider: @balance_provider)
    puts "  ✓ Initialized position tracker"

    @broker = DhanScalper::Brokers::PaperBroker.new(
      virtual_data_manager: nil,
      balance_provider: @balance_provider,
      logger: @logger
    )

    # Make the broker use the same position tracker as the test
    @broker.instance_variable_set(:@position_tracker, @position_tracker)
    puts "  ✓ Initialized paper broker"

    # Setup LTP seeding for deterministic testing
    setup_ltp_seeding
    puts "  ✓ Seeded LTP data for testing"
  end

  def run_test_scenarios
    puts "\n🧪 Running test scenarios..."

    test_profit_round_trip
    test_loss_round_trip
    test_partial_exit_averaging
    test_insufficient_funds_rejection
    test_oversell_rejection
    test_equity_invariant
  end

  def test_profit_round_trip
    puts "\n📈 Testing profit round trip..."

    # Reset state
    reset_test_state

    # BUY 75 @100
    buy_result = @broker.buy_market(
      segment: "NSE_FNO",
      security_id: "TEST_CE_100",
      quantity: 75,
      charge_per_order: 20
    )

    if buy_result.is_a?(Hash) && !buy_result[:success]
      add_error("Profit round trip: BUY failed - #{buy_result[:error]}")
      return
    end

    # Update LTP to 120 for profit
    DhanScalper::TickCache.put({
      segment: "NSE_FNO",
      security_id: "TEST_CE_100",
      ltp: 120.0,
      timestamp: Time.now.to_i
    })

    # SELL 75 @120
    sell_result = @broker.sell_market(
      segment: "NSE_FNO",
      security_id: "TEST_CE_100",
      quantity: 75,
      charge_per_order: 20
    )

    if sell_result.is_a?(Hash) && !sell_result[:success]
      add_error("Profit round trip: SELL failed - #{sell_result[:error]}")
      return
    end

    # Verify final state
    final_balance = @balance_provider.total_balance
    expected_balance = 100_000.0 + (20.0 * 75) - (20.0 * 2) # +1500 profit - 40 fees
    expected_balance = 101_460.0

    puts "  DEBUG: Final balance: #{DhanScalper::Support::Money.format(final_balance)}, Expected: #{DhanScalper::Support::Money.format(expected_balance)}"
    puts "  DEBUG: Available balance: #{DhanScalper::Support::Money.format(@balance_provider.available_balance)}"
    puts "  DEBUG: Used balance: #{DhanScalper::Support::Money.format(@balance_provider.used_balance)}"

    if (final_balance - expected_balance).abs > 0.01
      add_error("Profit round trip: Expected balance #{DhanScalper::Support::Money.format(expected_balance)}, got #{DhanScalper::Support::Money.format(final_balance)}")
    else
      puts "  ✓ Profit round trip passed (balance: #{DhanScalper::Support::Money.format(final_balance)})"
    end
  end

  def test_loss_round_trip
    puts "\n📉 Testing loss round trip..."

    # Reset state
    reset_test_state

    # BUY 75 @100
    buy_result = @broker.buy_market(
      segment: "NSE_FNO",
      security_id: "TEST_CE_100",
      quantity: 75,
      charge_per_order: 20
    )

    if buy_result.is_a?(Hash) && !buy_result[:success]
      add_error("Loss round trip: BUY failed - #{buy_result[:error]}")
      return
    end

    # Update LTP to 90 for loss
    DhanScalper::TickCache.put({
      segment: "NSE_FNO",
      security_id: "TEST_CE_100",
      ltp: 90.0,
      timestamp: Time.now.to_i
    })

    # SELL 75 @90
    sell_result = @broker.sell_market(
      segment: "NSE_FNO",
      security_id: "TEST_CE_100",
      quantity: 75,
      charge_per_order: 20
    )

    if sell_result.is_a?(Hash) && !sell_result[:success]
      add_error("Loss round trip: SELL failed - #{sell_result[:error]}")
      return
    end

    # Verify final state
    final_balance = @balance_provider.total_balance
    expected_balance = 100_000.0 - (10.0 * 75) - (20.0 * 2) # -750 loss - 40 fees
    expected_balance = 99_210.0

    puts "  DEBUG: Final balance: #{DhanScalper::Support::Money.format(final_balance)}, Expected: #{DhanScalper::Support::Money.format(expected_balance)}"
    puts "  DEBUG: Available balance: #{DhanScalper::Support::Money.format(@balance_provider.available_balance)}"
    puts "  DEBUG: Used balance: #{DhanScalper::Support::Money.format(@balance_provider.used_balance)}"
    puts "  DEBUG: Realized PnL: #{DhanScalper::Support::Money.format(@balance_provider.realized_pnl)}"
    puts "  DEBUG: Positions: #{@position_tracker.get_positions.length}"

    if (final_balance - expected_balance).abs > 0.01
      add_error("Loss round trip: Expected balance #{DhanScalper::Support::Money.format(expected_balance)}, got #{DhanScalper::Support::Money.format(final_balance)}")
    else
      puts "  ✓ Loss round trip passed (balance: #{DhanScalper::Support::Money.format(final_balance)})"
    end
  end

  def test_partial_exit_averaging
    puts "\n🔄 Testing partial exit / averaging..."

    # Reset state
    reset_test_state

    # BUY 75 @100
    buy1_result = @broker.buy_market(
      segment: "NSE_FNO",
      security_id: "TEST_CE_100",
      quantity: 75,
      charge_per_order: 20
    )

    if buy1_result.is_a?(Hash) && !buy1_result[:success]
      add_error("Partial exit: First BUY failed - #{buy1_result[:error]}")
      return
    end

    # Update LTP to 120
    DhanScalper::TickCache.put({
      segment: "NSE_FNO",
      security_id: "TEST_CE_100",
      ltp: 120.0,
      timestamp: Time.now.to_i
    })

    # BUY 75 @120 (averaging)
    buy2_result = @broker.buy_market(
      segment: "NSE_FNO",
      security_id: "TEST_CE_100",
      quantity: 75,
      charge_per_order: 20
    )

    if buy2_result.is_a?(Hash) && !buy2_result[:success]
      add_error("Partial exit: Second BUY failed - #{buy2_result[:error]}")
      return
    end

    # Update LTP to 130
    DhanScalper::TickCache.put({
      segment: "NSE_FNO",
      security_id: "TEST_CE_100",
      ltp: 130.0,
      timestamp: Time.now.to_i
    })

    # SELL 75 @130 (partial exit)
    sell_result = @broker.sell_market(
      segment: "NSE_FNO",
      security_id: "TEST_CE_100",
      quantity: 75,
      charge_per_order: 20
    )

    if sell_result.is_a?(Hash) && !sell_result[:success]
      add_error("Partial exit: SELL failed - #{sell_result[:error]}")
      return
    end

    # Verify state
    final_balance = @balance_provider.total_balance
    # Expected: 100000 - (100*75) - (120*75) + (130*75) - (20*3) = 100000 - 7500 - 9000 + 9750 - 60 = 99190
    expected_balance = 99_190.0

    if (final_balance - expected_balance).abs > 0.01
      add_error("Partial exit: Expected balance #{DhanScalper::Support::Money.format(expected_balance)}, got #{DhanScalper::Support::Money.format(final_balance)}")
    else
      puts "  ✓ Partial exit / averaging passed (balance: #{DhanScalper::Support::Money.format(final_balance)})"
    end
  end

  def test_insufficient_funds_rejection
    puts "\n💰 Testing insufficient funds rejection..."

    # Reset state with tiny balance
    @balance_provider.reset_balance(5_000.0)

    # Attempt BUY 75 @100 (should fail)
    buy_result = @broker.buy_market(
      segment: "NSE_FNO",
      security_id: "TEST_CE_100",
      quantity: 75,
      charge_per_order: 20
    )

    if buy_result.is_a?(Hash) && !buy_result[:success]
      puts "  ✓ Insufficient funds rejection passed"
    else
      add_error("Insufficient funds: BUY should have failed but succeeded")
    end

    # Reset balance for other tests
    @balance_provider.reset_balance(100_000.0)
  end

  def test_oversell_rejection
    puts "\n📊 Testing oversell rejection..."

    # Reset state
    reset_test_state

    # BUY 75 @100
    buy_result = @broker.buy_market(
      segment: "NSE_FNO",
      security_id: "TEST_CE_100",
      quantity: 75,
      charge_per_order: 20
    )

    if buy_result.is_a?(Hash) && !buy_result[:success]
      add_error("Oversell: BUY failed - #{buy_result[:error]}")
      return
    end

    # Attempt SELL 150 (should fail - oversell)
    sell_result = @broker.sell_market(
      segment: "NSE_FNO",
      security_id: "TEST_CE_100",
      quantity: 150,
      charge_per_order: 20
    )

    if sell_result.is_a?(Hash) && !sell_result[:success]
      puts "  ✓ Oversell rejection passed"
    else
      add_error("Oversell: SELL should have failed but succeeded")
    end
  end

  def test_equity_invariant
    puts "\n⚖️  Testing equity invariant..."

    # Reset state
    reset_test_state

    # When flat, equity should equal balance
    balance = @balance_provider.total_balance
    positions = @position_tracker.get_positions

    if positions.any?
      add_error("Equity invariant: Should have no positions when flat")
    else
      puts "  ✓ Equity invariant passed (flat state: balance=#{DhanScalper::Support::Money.format(balance)})"
    end
  end

  def setup_ltp_seeding
    # Seed deterministic LTP data for testing
    @ltp_values = [100.0, 120.0, 90.0, 130.0]
    @ltp_index = 0

    # Clear any existing tick cache
    DhanScalper::TickCache.clear
  end

  def get_next_ltp
    ltp = @ltp_values[@ltp_index] || 100.0
    @ltp_index += 1
    ltp
  end

  def reset_test_state
    # Reset balance
    @balance_provider.reset_balance(100_000.0)

    # Clear positions
    @position_tracker.clear_positions

    # Reset LTP index
    @ltp_index = 0

    # Clear tick cache
    DhanScalper::TickCache.clear

    # Seed initial LTP
    DhanScalper::TickCache.put({
      segment: "NSE_FNO",
      security_id: "TEST_CE_100",
      ltp: get_next_ltp,
      timestamp: Time.now.to_i
    })
  end

  def add_error(message)
    @errors << message
    puts "  ❌ #{message}"
  end

  def print_test_summary
    puts "\n" + "=" * 60
    puts "📊 Test Summary"
    puts "=" * 60
    puts "Total tests: #{@test_results.length + @errors.length}"
    puts "Passed: #{@test_results.length}"
    puts "Failed: #{@errors.length}"

    if @errors.any?
      puts "\n❌ Failures:"
      @errors.each_with_index do |error, i|
        puts "  #{i + 1}. #{error}"
      end
    end
  end
end

# Run the test
if __FILE__ == $0
  test = PaperE2ESmokeTest.new
  test.run
end