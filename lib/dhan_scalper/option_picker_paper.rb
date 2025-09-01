# frozen_string_literal: true

module DhanScalper
  class OptionPickerPaper
    def initialize(cfg) = (@cfg = cfg)

    def pick(current_spot:)
      expiry = nearest_weekly(@cfg["expiry_wday"])
      step = @cfg["strike_step"]
      atm = nearest_strike(current_spot, step)
      strikes = [atm - step, atm, atm + step].sort

      # Generate mock security IDs for paper trading
      { expiry: expiry, strikes: strikes,
        ce_sid: { (atm - step) => "PAPER_CE_#{atm - step}", atm => "PAPER_CE_#{atm}", (atm + step) => "PAPER_CE_#{atm + step}" },
        pe_sid: { (atm - step) => "PAPER_PE_#{atm - step}", atm => "PAPER_PE_#{atm}", (atm + step) => "PAPER_PE_#{atm + step}" } }
    end

    def nearest_strike(spot, step) = ((spot / step.to_f).round * step).to_i

    def nearest_weekly(wday)
      now = Time.now
      d = (wday - now.wday) % 7
      d = 7 if d.zero? && now.hour >= 15
      (now + d * 86_400).strftime("%Y-%m-%d")
    end
  end
end
