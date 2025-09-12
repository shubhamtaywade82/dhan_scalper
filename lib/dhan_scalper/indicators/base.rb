# frozen_string_literal: true

module DhanScalper
  module Indicators
    class Base
      attr_reader :series

      def initialize(series:)
        @series = series
      end

      # Convert CandleSeries to hash format expected by indicators
      def to_candle_hash
        {
          open: series.opens,
          high: series.highs,
          low: series.lows,
          close: series.closes,
          volume: series.volumes,
          timestamp: series.candles.map(&:timestamp),
        }
      end

      # Helper method to get last N values from an array
      def last_values(array, count)
        array.last(count)
      end

      # Helper method to check if we have enough data
      def sufficient_data?(required_count)
        series.candles.size >= required_count
      end
    end
  end
end
