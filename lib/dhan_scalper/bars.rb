# frozen_string_literal: true

module DhanScalper
  class Bars
    def self.closes(seg:, sid:, interval:)
      arr = DhanHQ::Models::HistoricalData.intraday(
        security_id: sid.to_s,
        exchange_segment: seg,
        instrument: seg == "IDX_I" ? "INDEX" : "OPTION",
        interval: interval.to_s
      )
      arr.map { |b| (b.respond_to?(:close) ? b.close : b[:close]).to_f }
    end

    def self.c1(seg:, sid:) = closes(seg: seg, sid: sid, interval: "1")
    def self.c3(seg:, sid:) = closes(seg: seg, sid: sid, interval: "3")
  end
end
