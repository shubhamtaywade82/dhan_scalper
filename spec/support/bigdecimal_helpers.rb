# frozen_string_literal: true

require "bigdecimal"
require "dhan_scalper/support/money"

# RSpec helpers for BigDecimal testing
module BigDecimalHelpers
  # Custom matcher for BigDecimal equality with precision
  def be_bigdecimal_equal(expected, precision: 2)
    be_within(BigDecimal("0.1")**precision).of(expected)
  end

  # Custom matcher for monetary values
  def be_monetary_equal(expected)
    be_bigdecimal_equal(DhanScalper::Support::Money.bd(expected))
  end

  # Helper to create BigDecimal test values
  def bd(value)
    DhanScalper::Support::Money.bd(value)
  end

  # Helper to create monetary test scenarios
  def create_monetary_scenario(base_amount, variations = {})
    {
      base: bd(base_amount),
      positive: bd(base_amount + (variations[:positive] || 100)),
      negative: bd(base_amount - (variations[:negative] || 100)),
      zero: bd(0),
      large: bd(base_amount * (variations[:large_multiplier] || 10)),
      small: bd(base_amount / (variations[:small_divisor] || 10)),
    }
  end

  # Helper to test monetary calculations
  def expect_monetary_calculation(operation, *, expected)
    result = DhanScalper::Support::Money.public_send(operation, *)
    expect(result).to be_monetary_equal(expected)
  end

  # Helper to test monetary precision
  def expect_monetary_precision(value, expected_precision)
    bd_value = DhanScalper::Support::Money.bd(value)
    decimal_places = bd_value.to_s("F").split(".").last&.length || 0
    expect(decimal_places).to be <= expected_precision
  end

  # Helper to test monetary formatting
  def expect_monetary_format(value, expected_format)
    formatted = DhanScalper::Support::Money.format(value)
    expect(formatted).to eq(expected_format)
  end

  # Helper to test monetary comparisons
  def expect_monetary_comparison(a, b, comparison)
    case comparison
    when :greater_than
      expect(DhanScalper::Support::Money.greater_than?(a, b)).to be true
    when :less_than
      expect(DhanScalper::Support::Money.less_than?(a, b)).to be true
    when :equal
      expect(DhanScalper::Support::Money.equal?(a, b)).to be true
    when :not_equal
      expect(DhanScalper::Support::Money.equal?(a, b)).to be false
    end
  end

  # Helper to test monetary operations with error handling
  def expect_monetary_operation_safe(operation, *args)
    expect { DhanScalper::Support::Money.public_send(operation, *args) }.not_to raise_error
  end

  # Helper to test monetary operations with specific errors
  def expect_monetary_operation_error(operation, *args, error_class)
    expect { DhanScalper::Support::Money.public_send(operation, *args) }.to raise_error(error_class)
  end

  # Helper to create test data for monetary calculations
  def create_monetary_test_data
    {
      small_amounts: [bd("0.01"), bd("0.1"), bd("1.0"), bd("10.0")],
      medium_amounts: [bd("100.0"), bd("1000.0"), bd("10000.0")],
      large_amounts: [bd("100000.0"), bd("1000000.0"), bd("10000000.0")],
      edge_cases: [bd("0"), bd("-0.01"), bd("-100.0"), bd("999999999.99")],
      precision_cases: [bd("0.001"), bd("0.0001"), bd("0.00001")],
    }
  end

  # Helper to test percentage calculations
  def expect_percentage_calculation(value, percentage, expected)
    result = DhanScalper::Support::Money.percentage(value, percentage)
    expect(result).to be_monetary_equal(expected)
  end

  # Helper to test percentage change calculations
  def expect_percentage_change(old_value, new_value, expected)
    result = DhanScalper::Support::Money.percentage_change(old_value, new_value)
    expect(result).to be_monetary_equal(expected)
  end

  # Helper to test monetary validation
  def expect_monetary_validation(value, validation_type)
    case validation_type
    when :positive
      expect(DhanScalper::Support::Money.positive?(value)).to be true
    when :negative
      expect(DhanScalper::Support::Money.negative?(value)).to be true
    when :zero
      expect(DhanScalper::Support::Money.zero?(value)).to be true
    when :not_zero
      expect(DhanScalper::Support::Money.zero?(value)).to be false
    end
  end

  # Helper to create realistic trading scenarios
  def create_trading_scenario
    {
      # NIFTY options trading scenario
      nifty_spot: bd("19500.0"),
      call_premium: bd("150.0"),
      put_premium: bd("120.0"),
      lot_size: 75,
      quantity: 1,
      charges: bd("20.0"),

      # Price movements
      price_up: bd("160.0"),
      price_down: bd("100.0"),

      # P&L calculations
      profit_target: bd("1000.0"),
      stop_loss: bd("500.0"),
    }
  end

  # Helper to test P&L calculations
  def expect_pnl_calculation(entry_price, exit_price, quantity, lot_size, expected_pnl)
    gross_pnl = (exit_price - entry_price) * quantity * lot_size
    expect(gross_pnl).to be_monetary_equal(expected_pnl)
  end

  # Helper to test position sizing
  def expect_position_sizing(available_balance, allocation_pct, premium, expected_quantity)
    allocated_amount = available_balance * allocation_pct
    expected_lots = (allocated_amount / premium).floor
    expect(expected_lots).to eq(expected_quantity)
  end

  # Helper to test risk management calculations
  def expect_risk_calculation(position_value, risk_pct, expected_risk_amount)
    risk_amount = position_value * risk_pct
    expect(risk_amount).to be_monetary_equal(expected_risk_amount)
  end

  # Helper to test compound calculations
  def expect_compound_calculation(principal, rate, periods, expected)
    result = principal
    periods.times { result *= (1 + rate) }
    expect(result).to be_monetary_equal(expected)
  end

  # Helper to test rounding scenarios
  def expect_rounding_scenario(value, precision, expected)
    rounded = DhanScalper::Support::Money.bd(value).round(precision)
    expect(rounded).to be_monetary_equal(expected)
  end

  # Helper to test edge cases
  def expect_edge_case_handling(value, expected_behavior)
    case expected_behavior
    when :converts_to_bigdecimal
      expect(DhanScalper::Support::Money.bd(value)).to be_a(BigDecimal)
    when :handles_nil
      expect(DhanScalper::Support::Money.bd(value)).to eq(bd(0))
    when :handles_string
      expect(DhanScalper::Support::Money.bd(value)).to be_a(BigDecimal)
    when :handles_numeric
      expect(DhanScalper::Support::Money.bd(value)).to be_a(BigDecimal)
    end
  end
end

# Include helpers in RSpec configuration
RSpec.configure do |config|
  config.include BigDecimalHelpers
end
