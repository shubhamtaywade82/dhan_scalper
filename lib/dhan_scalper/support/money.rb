# frozen_string_literal: true

require 'bigdecimal'

module DhanScalper
  module Support
    # Money utilities for safe financial calculations using BigDecimal
    module Money
      module_function

      # Convert value to BigDecimal for safe money calculations
      # @param value [String, Numeric, BigDecimal] The value to convert
      # @return [BigDecimal] The value as BigDecimal
      def bd(value)
        case value
        when BigDecimal
          value
        when String
          BigDecimal(value)
        when Numeric
          BigDecimal(value.to_s)
        when nil
          BigDecimal(0)
        else
          BigDecimal(value.to_s)
        end
      end

      # Convert BigDecimal to canonical string representation
      # @param value [BigDecimal, Numeric] The value to convert
      # @return [String] Canonical string representation
      def dec(value)
        bd(value).to_s('F')
      end

      # Round BigDecimal to 2 decimal places for presentation
      # @param value [BigDecimal, Numeric] The value to round
      # @return [BigDecimal] Rounded to 2 decimal places
      def round2(value)
        bd(value).round(2)
      end

      # Add two monetary values safely
      # @param a [BigDecimal, Numeric] First value
      # @param b [BigDecimal, Numeric] Second value
      # @return [BigDecimal] Sum as BigDecimal
      def add(a, b)
        bd(a) + bd(b)
      end

      # Subtract two monetary values safely
      # @param a [BigDecimal, Numeric] First value
      # @param b [BigDecimal, Numeric] Second value
      # @return [BigDecimal] Difference as BigDecimal
      def subtract(a, b)
        bd(a) - bd(b)
      end

      # Multiply monetary value by a factor safely
      # @param value [BigDecimal, Numeric] The monetary value
      # @param factor [BigDecimal, Numeric] The multiplication factor
      # @return [BigDecimal] Product as BigDecimal
      def multiply(value, factor)
        bd(value) * bd(factor)
      end

      # Divide monetary value by a divisor safely
      # @param value [BigDecimal, Numeric] The monetary value
      # @param divisor [BigDecimal, Numeric] The divisor
      # @return [BigDecimal] Quotient as BigDecimal
      def divide(value, divisor)
        bd(value) / bd(divisor)
      end

      # Check if two monetary values are equal (within precision)
      # @param a [BigDecimal, Numeric] First value
      # @param b [BigDecimal, Numeric] Second value
      # @param precision [Integer] Decimal places for comparison (default: 2)
      # @return [Boolean] True if values are equal within precision
      def equal?(a, b, precision: 2)
        bd(a).round(precision) == bd(b).round(precision)
      end

      # Check if first value is greater than second
      # @param a [BigDecimal, Numeric] First value
      # @param b [BigDecimal, Numeric] Second value
      # @return [Boolean] True if a > b
      def greater_than?(a, b)
        bd(a) > bd(b)
      end

      # Check if first value is less than second
      # @param a [BigDecimal, Numeric] First value
      # @param b [BigDecimal, Numeric] Second value
      # @return [Boolean] True if a < b
      def less_than?(a, b)
        bd(a) < bd(b)
      end

      # Check if first value is greater than or equal to second
      # @param a [BigDecimal, Numeric] First value
      # @param b [BigDecimal, Numeric] Second value
      # @return [Boolean] True if a >= b
      def greater_than_or_equal?(a, b)
        bd(a) >= bd(b)
      end

      # Check if first value is less than or equal to second
      # @param a [BigDecimal, Numeric] First value
      # @param b [BigDecimal, Numeric] Second value
      # @return [Boolean] True if a <= b
      def less_than_or_equal?(a, b)
        bd(a) <= bd(b)
      end

      # Get absolute value of monetary amount
      # @param value [BigDecimal, Numeric] The value
      # @return [BigDecimal] Absolute value
      def abs(value)
        bd(value).abs
      end

      # Check if value is zero
      # @param value [BigDecimal, Numeric] The value
      # @return [Boolean] True if value is zero
      def zero?(value)
        bd(value).zero?
      end

      # Check if value is positive
      # @param value [BigDecimal, Numeric] The value
      # @return [Boolean] True if value is positive
      def positive?(value)
        bd(value).positive?
      end

      # Check if value is negative
      # @param value [BigDecimal, Numeric] The value
      # @return [Boolean] True if value is negative
      def negative?(value)
        bd(value).negative?
      end

      # Format monetary value for display
      # @param value [BigDecimal, Numeric] The value
      # @param precision [Integer] Decimal places (default: 2)
      # @return [String] Formatted string
      def format(value, precision: 2)
        rounded = bd(value).round(precision)
        "₹#{rounded.to_s('F')}"
      end

      # Calculate percentage of a monetary value
      # @param value [BigDecimal, Numeric] The base value
      # @param percentage [BigDecimal, Numeric] The percentage (e.g., 15 for 15%)
      # @return [BigDecimal] Percentage amount
      def percentage(value, percentage)
        multiply(value, divide(percentage, 100))
      end

      # Calculate percentage change between two values
      # @param old_value [BigDecimal, Numeric] The original value
      # @param new_value [BigDecimal, Numeric] The new value
      # @return [BigDecimal] Percentage change
      def percentage_change(old_value, new_value)
        return BigDecimal(0) if zero?(old_value)

        change = subtract(new_value, old_value)
        multiply(divide(change, old_value), 100)
      end

      # Get maximum of two values
      # @param a [BigDecimal, Numeric] First value
      # @param b [BigDecimal, Numeric] Second value
      # @return [BigDecimal] Maximum value
      def max(a, b)
        a_bd = bd(a)
        b_bd = bd(b)
        [a_bd, b_bd].max
      end

      # Get minimum of two values
      # @param a [BigDecimal, Numeric] First value
      # @param b [BigDecimal, Numeric] Second value
      # @return [BigDecimal] Minimum value
      def min(a, b)
        a_bd = bd(a)
        b_bd = bd(b)
        [a_bd, b_bd].min
      end
    end
  end
end
