# frozen_string_literal: true

module DhanScalper
  class OptionPicker
    def initialize(cfg) = (@cfg = cfg)

    def pick(current_spot:)
      expiry = nearest_weekly(@cfg.fetch("expiry_wday"))
      step   = @cfg.fetch("strike_step")
      atm    = nearest_strike(current_spot, step)
      strikes = [atm - step, atm, atm + step].sort
      oc = DhanHQ::Models::OptionChain.fetch(
        underlying_scrip: @cfg.fetch("idx_sid"),
        underlying_seg: @cfg.fetch("seg_opt"),
        expiry: expiry
      )
      by = index_by(oc)
      {
        expiry: expiry, strikes: strikes,
        ce_sid: { (atm-step)=>by[[atm-step,:CE]], atm=>by[[atm,:CE]], (atm+step)=>by[[atm+step,:CE]] },
        pe_sid: { (atm-step)=>by[[atm-step,:PE]], atm=>by[[atm,:PE]], (atm+step)=>by[[atm+step,:PE]] }
      }
    end

    def nearest_strike(spot, step) = ((spot / step.to_f).round * step).to_i

    def nearest_weekly(wday_target)
      now = Time.now
      d = (wday_target - now.wday) % 7
      d = 7 if d == 0 && now.hour >= 15
      (now + d*86_400).strftime("%Y-%m-%d")
    end

    def index_by(chain)
      h = {}
      chain.each do |row|
        strike = (row.respond_to?(:strike) ? row.strike : row[:strike]).to_i
        opt    = (row.respond_to?(:option_type) ? row.option_type : row[:option_type]).to_s.upcase.to_sym
        sid    = (row.respond_to?(:security_id) ? row.security_id : row[:security_id]).to_s
        h[[strike,opt]] = sid
      end
      h
    end
  end
end