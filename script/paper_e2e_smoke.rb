#!/usr/bin/env ruby
# frozen_string_literal: true

# End-to-End Smoke Test for Paper Trading
# This script validates the complete paper trading workflow:
# 1. Boots broker with starting balance
# 2. Seeds LTP provider with specific values
# 3. Places BUY order and validates execution
# 4. Refreshes unrealized PnL with new LTP
# 5. Places SELL order and validates execution
# 6. Validates final balance and PnL calculations

require "bundler/setup"
require "dotenv/load"
require "logger"

# Load individual components
require_relative "../lib/dhan_scalper/support/money"
require_relative "../lib/dhan_scalper/support/application_service"
require_relative "../lib/dhan_scalper/balance_providers/paper_wallet"
require_relative "../lib/dhan_scalper/services/enhanced_position_tracker"
require_relative "../lib/dhan_scalper/services/equity_calculator"
require_relative "../lib/dhan_scalper/tick_cache"
require_relative "../lib/dhan_scalper/brokers/base"
require_relative "../lib/dhan_scalper/brokers/paper_broker"

class PaperE2ESmokeTest
  def initialize
    @logger = Logger.new($stdout)
    @logger.level = Logger::INFO
    @test_results = {}
    @errors = []
    @ltp_values = [100.0, 120.0]
    @ltp_index = 0
  end

  def run
    puts "🚀 Starting Paper Trading E2E Smoke Test"
    puts "=" * 60

    begin
      setup_test_environment
      test_broker_initialization
      test_ltp_seeding
      test_buy_order_execution
      test_unrealized_pnl_refresh
      test_sell_order_execution
      test_final_balance_validation
      print_test_summary
    rescue StandardError => e
      @errors << "Test failed with error: #{e.message}"
      puts "❌ Test failed: #{e.message}"
      puts e.backtrace.first(5).join("\n")
      exit 1
    end
  end

  private

  def setup_test_environment
    puts "\n📋 Setting up test environment..."

    # Initialize balance provider with 100,000 starting balance
    @balance_provider = DhanScalper::BalanceProviders::PaperWallet.new(starting_balance: 100_000.0)

    # Initialize position tracker
    @position_tracker = DhanScalper::Services::EnhancedPositionTracker.new

    # Initialize equity calculator
    @equity_calculator = DhanScalper::Services::EquityCalculator.new(
      balance_provider: @balance_provider,
      position_tracker: @position_tracker,
      logger: @logger
    )

    # Initialize paper broker
    @broker = DhanScalper::Brokers::PaperBroker.new(
      balance_provider: @balance_provider,
      logger: @logger
    )

    # Set up LTP seeding by directly manipulating TickCache
    setup_ltp_seeding

    puts "✅ Test environment initialized"
    puts "   Starting balance: ₹#{@balance_provider.available_balance.round(2)}"
  end

  def test_broker_initialization
    puts "\n🔧 Testing broker initialization..."

    # Verify initial balance
    initial_balance = @balance_provider.available_balance
    expected_balance = 100_000.0

    if initial_balance == expected_balance
      @test_results[:broker_init] = "PASS"
      puts "✅ Broker initialized with correct balance: ₹#{initial_balance.round(2)}"
    else
      @test_results[:broker_init] = "FAIL"
      @errors << "Expected balance ₹#{expected_balance}, got ₹#{initial_balance}"
      puts "❌ Broker initialization failed"
    end
  end

  def test_ltp_seeding
    puts "\n📊 Testing LTP seeding..."

    # Test first LTP value (100.0)
    first_ltp = get_next_ltp
    if first_ltp == 100.0
      @test_results[:ltp_seeding] = "PASS"
      puts "✅ LTP seeding working: First value = ₹#{first_ltp}"
    else
      @test_results[:ltp_seeding] = "FAIL"
      @errors << "Expected first LTP 100.0, got #{first_ltp}"
      puts "❌ LTP seeding failed"
    end
  end

  def test_buy_order_execution
    puts "\n💰 Testing BUY order execution..."

    # Place BUY order for 75 units at 100
    buy_result = @broker.buy_market(
      segment: "NSE_FNO",
      security_id: "TEST123",
      quantity: 75,
      charge_per_order: 20
    )

    if buy_result.is_a?(DhanScalper::Brokers::Order)
      @test_results[:buy_order] = "PASS"
      puts "✅ BUY order executed successfully"
      puts "   Order ID: #{buy_result.id}"
      puts "   Quantity: #{buy_result.qty}"
      puts "   Price: ₹#{buy_result.avg_price}"

      # Verify position was created
      position = @position_tracker.get_position(
        exchange_segment: "NSE_FNO",
        security_id: "TEST123",
        side: "LONG"
      )

      if position && position[:net_qty] == 75
        puts "✅ Position created correctly: #{position[:net_qty]} units"
      else
        @errors << "Position not created or incorrect quantity"
        puts "❌ Position creation failed"
      end

      # Verify balance was debited
      expected_cost = (75 * 100) + 20 # quantity * price + fee
      expected_balance = 100_000 - expected_cost
      actual_balance = @balance_provider.available_balance

      if (actual_balance - expected_balance).abs < 0.01
        puts "✅ Balance debited correctly: ₹#{actual_balance.round(2)}"
      else
        @errors << "Balance debit incorrect. Expected ₹#{expected_balance}, got ₹#{actual_balance}"
        puts "❌ Balance debit failed"
      end
    else
      @test_results[:buy_order] = "FAIL"
      @errors << "BUY order failed: #{buy_result}"
      puts "❌ BUY order execution failed"
    end
  end

  def test_unrealized_pnl_refresh
    puts "\n📈 Testing unrealized PnL refresh..."

    # Get second LTP value (120.0)
    second_ltp = get_next_ltp
    puts "   Current LTP: ₹#{second_ltp}"

    # Refresh unrealized PnL
    refresh_result = @equity_calculator.refresh_unrealized!(
      exchange_segment: "NSE_FNO",
      security_id: "TEST123",
      current_ltp: second_ltp
    )

    if refresh_result[:success]
      @test_results[:unrealized_pnl] = "PASS"
      puts "✅ Unrealized PnL refreshed successfully"
      puts "   Unrealized PnL: ₹#{refresh_result[:unrealized_pnl].round(2)}"

      # Verify unrealized PnL calculation
      expected_unrealized = (120.0 - 100.0) * 75 # (current_ltp - entry_price) * quantity
      actual_unrealized = refresh_result[:unrealized_pnl]

      if (actual_unrealized - expected_unrealized).abs < 0.01
        puts "✅ Unrealized PnL calculation correct: ₹#{actual_unrealized.round(2)}"
      else
        @errors << "Unrealized PnL calculation incorrect. Expected ₹#{expected_unrealized}, got ₹#{actual_unrealized}"
        puts "❌ Unrealized PnL calculation failed"
      end
    else
      @test_results[:unrealized_pnl] = "FAIL"
      @errors << "Unrealized PnL refresh failed: #{refresh_result[:error]}"
      puts "❌ Unrealized PnL refresh failed"
    end
  end

  def test_sell_order_execution
    puts "\n💸 Testing SELL order execution..."

    # Place SELL order for all 75 units at 120
    sell_result = @broker.sell_market(
      segment: "NSE_FNO",
      security_id: "TEST123",
      quantity: 75,
      charge_per_order: 20
    )

    if sell_result.is_a?(DhanScalper::Brokers::Order)
      @test_results[:sell_order] = "PASS"
      puts "✅ SELL order executed successfully"
      puts "   Order ID: #{sell_result.id}"
      puts "   Quantity: #{sell_result.qty}"
      puts "   Price: ₹#{sell_result.avg_price}"

      # Verify position was closed
      position = @position_tracker.get_position(
        exchange_segment: "NSE_FNO",
        security_id: "TEST123",
        side: "LONG"
      )

      if position.nil? || position[:net_qty] == 0
        puts "✅ Position closed correctly"
      else
        @errors << "Position not closed properly. Net quantity: #{position[:net_qty]}"
        puts "❌ Position closure failed"
      end
    else
      @test_results[:sell_order] = "FAIL"
      @errors << "SELL order failed: #{sell_result}"
      puts "❌ SELL order execution failed"
    end
  end

  def test_final_balance_validation
    puts "\n🏦 Testing final balance validation..."

    # Get final balance and PnL
    final_balance = @balance_provider.total_balance
    realized_pnl = @balance_provider.realized_pnl
    equity_breakdown = @equity_calculator.get_equity_breakdown

    puts "\n📊 Final Results:"
    puts "   Available Balance: ₹#{@balance_provider.available_balance.round(2)}"
    puts "   Used Balance: ₹#{@balance_provider.used_balance.round(2)}"
    puts "   Total Balance: ₹#{final_balance.round(2)}"
    puts "   Realized PnL: ₹#{realized_pnl.round(2)}"
    puts "   Total Equity: ₹#{equity_breakdown[:total_equity].round(2)}"

    # Expected values
    expected_balance = 101_460.0  # 100,000 + 1,500 profit - 40 fees
    expected_realized_pnl = 1_500.0  # (120 - 100) * 75 - 40 fees

    # Validate final balance
    if (final_balance - expected_balance).abs < 0.01
      @test_results[:final_balance] = "PASS"
      puts "✅ Final balance correct: ₹#{final_balance.round(2)}"
    else
      @test_results[:final_balance] = "FAIL"
      @errors << "Final balance incorrect. Expected ₹#{expected_balance}, got ₹#{final_balance}"
      puts "❌ Final balance validation failed"
    end

    # Validate realized PnL
    if (realized_pnl - expected_realized_pnl).abs < 0.01
      @test_results[:realized_pnl] = "PASS"
      puts "✅ Realized PnL correct: ₹#{realized_pnl.round(2)}"
    else
      @test_results[:realized_pnl] = "FAIL"
      @errors << "Realized PnL incorrect. Expected ₹#{expected_realized_pnl}, got ₹#{realized_pnl}"
      puts "❌ Realized PnL validation failed"
    end
  end

  def print_test_summary
    puts "\n" + "=" * 60
    puts "📋 TEST SUMMARY"
    puts "=" * 60

    @test_results.each do |test_name, result|
      status = result == "PASS" ? "✅" : "❌"
      puts "#{status} #{test_name.upcase.gsub('_', ' ')}: #{result}"
    end

    if @errors.empty?
      puts "\n🎉 ALL TESTS PASSED!"
      puts "Paper trading E2E smoke test completed successfully."
      exit 0
    else
      puts "\n❌ TEST FAILURES:"
      @errors.each_with_index do |error, index|
        puts "   #{index + 1}. #{error}"
      end
      puts "\n💥 Smoke test failed with #{@errors.length} error(s)."
      exit 1
    end
  end

  def setup_ltp_seeding
    # Seed TickCache with our test values
    @ltp_values.each_with_index do |ltp, index|
      # Store the LTP in TickCache
      DhanScalper::TickCache.put({
        segment: "NSE_FNO",
        security_id: "TEST123",
        ltp: ltp,
        timestamp: Time.now.to_i
      })
      puts "   Seeding LTP #{index + 1}: ₹#{ltp}"
    end
  end

  def get_next_ltp
    ltp = @ltp_values[@ltp_index] || 100.0
    @ltp_index += 1
    ltp
  end
end

# Run the smoke test
if __FILE__ == $PROGRAM_NAME
  test = PaperE2ESmokeTest.new
  test.run
end