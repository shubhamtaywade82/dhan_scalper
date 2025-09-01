# frozen_string_literal: true

require "date"

module DhanScalper
  module MarketCalendar
    MARKET_HOLIDAYS = [
      # Add static or API-fetched holiday dates here
      Date.new(2025, 8, 15),
      Date.new(2025, 8, 27)
      # ...
    ].freeze

    def self.trading_day?(date)
      weekday = date.wday.between?(1, 5) # Monday to Friday
      !MARKET_HOLIDAYS.include?(date) && weekday
    end

    def self.last_trading_day(from: Date.today)
      date = from
      date -= 1 until trading_day?(date)
      date
    end

    def self.today_or_last_trading_day
      trading_day?(Date.today) ? Date.today : last_trading_day
    end
  end

  class Bars
    def self.intraday_ohlc(seg:, sid:, interval: nil, oi: false, from_date: nil, to_date: nil)
      to_date ||= MarketCalendar.today_or_last_trading_day.to_s
      from_date ||= (Date.parse(to_date) - 90).to_s # fetch last 90 days by default

      DhanHQ::Models::HistoricalData.intraday(
        security_id: sid.to_s,
        exchange_segment: seg,
        instrument: seg == "IDX_I" ? "INDEX" : "OPTION",
        interval: interval || "5",
        oi: oi,
        from_date: from_date,
        to_date: to_date
      )
    rescue StandardError => e
      puts "Failed to fetch Historical OHLC for Instrument #{sid}: #{e.message}"
      nil
    end

    def self.closes(seg:, sid:, interval:)
      # Always use real API for market data, even in paper mode
      arr = intraday_ohlc(seg: seg, sid: sid, interval: interval)
      return [] unless arr

      arr.map do |b|
        if b.respond_to?(:close)
          b.close.to_f
        elsif b.is_a?(Hash) && b.key?(:close)
          b[:close].to_f
        elsif b.is_a?(Hash) && b.key?("close")
          b["close"].to_f
        else
          # Fallback: try to extract close price from any numeric field
          b.values.find { |v| v.is_a?(Numeric) }.to_f
        end
      end
    end

    def self.c1(seg:, sid:) = closes(seg: seg, sid: sid, interval: "1")
    def self.c3(seg:, sid:) = closes(seg: seg, sid: sid, interval: "3")
  end
end
