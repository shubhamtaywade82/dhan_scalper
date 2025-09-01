# frozen_string_literal: true

module DhanScalper
  class OptionPickerPaper
    def initialize(cfg) = (@cfg = cfg)

        def pick(current_spot:)
      expiry = nearest_weekly(@cfg.fetch("expiry_wday"))
      step   = @cfg.fetch("strike_step")
      atm    = nearest_strike(current_spot, step)
      strikes = [atm - step, atm, atm + step].sort

      # Try real API first, fallback to mock data if it fails
      begin
        oc = DhanHQ::Models::OptionChain.fetch(
          underlying_scrip: @cfg.fetch("idx_sid"),
          underlying_seg: @cfg.fetch("seg_idx"),  # Use IDX_I, not NSE_FNO
          expiry: expiry
        )
        by = index_by(oc)
        {
          expiry: expiry, strikes: strikes,
          ce_sid: { (atm-step)=>by[[atm-step,:CE]], atm=>by[[atm,:CE]], (atm+step)=>by[[atm+step,:CE]] },
          pe_sid: { (atm-step)=>by[[atm-step,:PE]], atm=>by[[atm,:PE]], (atm+step)=>by[[atm+step,:PE]] }
        }
      rescue StandardError => e
        puts "Warning: Option chain API failed (#{e.message}), using mock data for paper trading"
        # Generate mock option chain data for paper trading
        {
          expiry: expiry, strikes: strikes,
          ce_sid: {
            (atm-step) => "PAPER_CE_#{atm-step}",
            atm => "PAPER_CE_#{atm}",
            (atm+step) => "PAPER_CE_#{atm+step}"
          },
          pe_sid: {
            (atm-step) => "PAPER_PE_#{atm-step}",
            atm => "PAPER_PE_#{atm}",
            (atm+step) => "PAPER_PE_#{atm+step}"
          }
        }
      end
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