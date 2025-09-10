# frozen_string_literal: true

require "logger"

module DhanScalper
  module UI
    class SimpleLogger
      def initialize(state, balance_provider: nil)
        @state = state
        @balance_provider = balance_provider
        @logger = Logger.new($stdout)
        @logger.level = Logger::INFO
        @logger.formatter = proc do |_severity, datetime, _progname, msg|
          "[#{datetime.strftime("%H:%M:%S")}] #{msg}\n"
        end
        @last_update = Time.at(0)
        @update_interval = 60 # Update every 60 seconds
      end

      def run
        # This is a no-op for the simple logger
        # It will be called periodically from the main loop
      end

      def update_status(traders = {})
        return unless Time.now - @last_update >= @update_interval

        @last_update = Time.now
        gpn = @state.pnl
        open_positions = traders.values.compact.count { |t| t&.instance_variable_get(:@open) }

        status_msg = "Status: #{@state.status.upcase} | PnL: ₹#{gpn.round(0)} | Open: #{open_positions}"

        if @balance_provider
          available = @balance_provider.available_balance
          used = @balance_provider.used_balance
          status_msg += " | Balance: ₹#{available.round(0)} (Used: ₹#{used.round(0)})"
        end

        @logger.info(status_msg)
      end

      def log_trade(symbol, side, quantity, price, reason = nil)
        trade_msg = "#{side} #{quantity} #{symbol} @ ₹#{price}"
        trade_msg += " (#{reason})" if reason
        @logger.info("TRADE: #{trade_msg}")
      end

      def log_signal(symbol, direction, confidence = nil)
        signal_msg = "SIGNAL: #{symbol} #{direction.upcase}"
        signal_msg += " (confidence: #{confidence})" if confidence
        @logger.info(signal_msg)
      end

      def log_error(message)
        @logger.error("ERROR: #{message}")
      end

      def log_info(message)
        @logger.info(message)
      end
    end
  end
end
