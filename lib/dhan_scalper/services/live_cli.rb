# frozen_string_literal: true

require "logger"
require_relative "../services/market_feed"

module DhanScalper
  module Services
    # Simple live LTP display service extracted from CLI
    class LiveCLIService
      def initialize(interval: 1.0, logger: Logger.new($stdout))
        @interval = interval.to_f
        @logger = logger
      end

      def run(instruments)
        market_feed = DhanScalper::Services::MarketFeed.new(mode: :quote)
        market_feed.start(instruments)

        puts "Live LTP Data (Press Ctrl+C to stop)"
        puts "=" * 50

        loop do
          sleep(@interval)
          clear_screen
          puts "Live LTP Data - #{Time.now.strftime("%H:%M:%S")}"
          puts "=" * 50

          instruments.each do |instrument|
            ltp = market_feed.ltp(instrument[:segment], instrument[:security_id])
            puts "#{instrument[:name]}: #{ltp ? "₹#{ltp}" : "N/A"}"
          end

          puts "\nPress Ctrl+C to stop"
        end
      rescue Interrupt
        puts "\nStopping live data feed..."
      ensure
        market_feed&.stop
      end

      private

      def clear_screen
        system("clear") || system("cls")
      end
    end
  end
end

