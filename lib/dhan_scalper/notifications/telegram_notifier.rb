# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module DhanScalper
  module Notifications
    # Telegram notifier for trade events and alerts
    class TelegramNotifier
      attr_reader :bot_token, :chat_id, :enabled, :logger

      def initialize(bot_token: nil, chat_id: nil, enabled: true, logger: nil)
        @bot_token = bot_token || ENV.fetch("TELEGRAM_BOT_TOKEN", nil)
        @chat_id = chat_id || ENV.fetch("TELEGRAM_CHAT_ID", nil)
        @enabled = enabled && @bot_token && @chat_id
        @logger = logger || Logger.new($stdout)
      end

      def notify_entry(symbol, option_type, strike, premium, quantity, side)
        return unless @enabled

        message = <<~MESSAGE
          🚀 **ENTRY PLACED**

          **Symbol:** #{symbol}
          **Option:** #{option_type} #{strike}
          **Side:** #{side}
          **Quantity:** #{quantity}
          **Premium:** ₹#{premium.round(2)}
          **Time:** #{Time.now.strftime("%H:%M:%S")}
        MESSAGE

        send_message(message)
      end

      def notify_exit(symbol, option_type, strike, exit_price, pnl, reason)
        return unless @enabled

        pnl_emoji = pnl >= 0 ? "💰" : "📉"

        message = <<~MESSAGE
          #{pnl_emoji} **EXIT EXECUTED**

          **Symbol:** #{symbol}
          **Option:** #{option_type} #{strike}
          **Exit Price:** ₹#{exit_price.round(2)}
          **P&L:** ₹#{pnl.round(2)}
          **Reason:** #{reason}
          **Time:** #{Time.now.strftime("%H:%M:%S")}
        MESSAGE

        send_message(message)
      end

      def notify_adjustment(symbol, option_type, strike, old_trigger, new_trigger, peak_price)
        return unless @enabled

        message = <<~MESSAGE
          🔧 **STOP LOSS ADJUSTED**

          **Symbol:** #{symbol}
          **Option:** #{option_type} #{strike}
          **Old Trigger:** ₹#{old_trigger.round(2)}
          **New Trigger:** ₹#{new_trigger.round(2)}
          **Peak Price:** ₹#{peak_price.round(2)}
          **Time:** #{Time.now.strftime("%H:%M:%S")}
        MESSAGE

        send_message(message)
      end

      def notify_emergency(symbol, reason, pnl)
        return unless @enabled

        message = <<~MESSAGE
          🚨 **EMERGENCY EXIT**

          **Symbol:** #{symbol}
          **Reason:** #{reason}
          **P&L:** ₹#{pnl.round(2)}
          **Time:** #{Time.now.strftime("%H:%M:%S")}
        MESSAGE

        send_message(message, parse_mode: "Markdown")
      end

      def notify_heartbeat(equity, positions_count, last_feed_time)
        return unless @enabled

        message = <<~MESSAGE
          💓 **HEARTBEAT**

          **Equity:** ₹#{equity.round(0)}
          **Open Positions:** #{positions_count}
          **Last Feed:** #{last_feed_time.strftime("%H:%M:%S")}
          **Time:** #{Time.now.strftime("%H:%M:%S")}
        MESSAGE

        send_message(message)
      end

      def notify_eod_summary(summary)
        return unless @enabled

        message = <<~MESSAGE
          📊 **EOD SUMMARY**

          **Total Trades:** #{summary[:total_trades]}
          **Win Rate:** #{summary[:win_rate]}%
          **Total P&L:** ₹#{summary[:total_pnl].round(2)}
          **Max Drawdown:** ₹#{summary[:max_drawdown].round(2)}
          **Best Trade:** ₹#{summary[:best_trade].round(2)}
          **Worst Trade:** ₹#{summary[:worst_trade].round(2)}
        MESSAGE

        send_message(message)
      end

      def notify_error(error_message, context = nil)
        return unless @enabled

        message = <<~MESSAGE
          ❌ **ERROR**

          **Message:** #{error_message}
          **Context:** #{context}
          **Time:** #{Time.now.strftime("%H:%M:%S")}
        MESSAGE

        send_message(message)
      end

      private

      def send_message(text, parse_mode: "Markdown")
        return false unless @enabled

        uri = URI("https://api.telegram.org/bot#{@bot_token}/sendMessage")

        payload = {
          chat_id: @chat_id,
          text: text,
          parse_mode: parse_mode,
        }

        begin
          response = Net::HTTP.post_form(uri, payload)
          result = JSON.parse(response.body)

          if result["ok"]
            @logger.debug "[TELEGRAM] Message sent successfully"
            true
          else
            @logger.error "[TELEGRAM] Failed to send message: #{result["description"]}"
            false
          end
        rescue StandardError => e
          @logger.error "[TELEGRAM] Error sending message: #{e.message}"
          false
        end
      end
    end
  end
end
