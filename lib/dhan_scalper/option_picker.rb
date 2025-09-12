# frozen_string_literal: true

require_relative "csv_master"

module DhanScalper
  class OptionPicker
    def initialize(cfg, mode: :live, csv_master: nil)
      @cfg = cfg
      @mode = mode
      @csv_master = csv_master || CsvMaster.new
    end

    def pick(current_spot:)
      # Get available expiry dates from CSV master data
      expiry = fetch_first_expiry
      return nil unless expiry

      step   = @cfg.fetch("strike_step")
      atm    = nearest_strike(current_spot, step)
      strikes = [atm - step, atm, atm + step].sort

      # Get security IDs from CSV master data
      begin
        underlying_symbol = get_underlying_symbol
        ce_sid = {}
        pe_sid = {}

        strikes.each do |strike|
          # Get Call option security ID
          ce_security_id = @csv_master.get_security_id(underlying_symbol, expiry, strike, "CE")
          ce_sid[strike] = ce_security_id || "PAPER_CE_#{strike}"

          # Get Put option security ID
          pe_security_id = @csv_master.get_security_id(underlying_symbol, expiry, strike, "PE")
          pe_sid[strike] = pe_security_id || "PAPER_PE_#{strike}"
        end

        {
          expiry: expiry, strikes: strikes,
          ce_sid: ce_sid,
          pe_sid: pe_sid
        }
      rescue StandardError => e
        raise "Failed to fetch option chain for live trading: #{e.message}" unless @mode == :paper

        puts "Warning: CSV master lookup failed (#{e.message}), using mock data for paper trading"
        # Generate mock option chain data for paper trading
        {
          expiry: expiry, strikes: strikes,
          ce_sid: {
            (atm - step) => "PAPER_CE_#{atm - step}",
            atm => "PAPER_CE_#{atm}",
            (atm + step) => "PAPER_CE_#{atm + step}"
          },
          pe_sid: {
            (atm - step) => "PAPER_PE_#{atm - step}",
            atm => "PAPER_PE_#{atm}",
            (atm + step) => "PAPER_PE_#{atm + step}"
          }
        }

        # For live trading, re-raise the error
      end
    end

    def pick_atm_strike(current_spot, signal)
      # Get available expiry dates from CSV master data
      expiry = fetch_first_expiry
      return nil unless expiry

      step = @cfg.fetch("strike_step")
      atm = nearest_strike(current_spot, step)

      # Determine strike selection based on signal strength and direction
      selected_strike = select_strike_for_signal(atm, step, signal, current_spot)

      begin
        underlying_symbol = get_underlying_symbol

        # Get security IDs for the selected strike
        ce_security_id = @csv_master.get_security_id(underlying_symbol, expiry, selected_strike, "CE")
        pe_security_id = @csv_master.get_security_id(underlying_symbol, expiry, selected_strike, "PE")

        # Get premium prices (mock for paper trading)
        premium = get_option_premium(selected_strike, current_spot, signal)

        {
          strike: selected_strike,
          expiry: expiry,
          ce_security_id: ce_security_id || "PAPER_CE_#{selected_strike}",
          pe_security_id: pe_security_id || "PAPER_PE_#{selected_strike}",
          premium: premium
        }
      rescue StandardError => e
        raise "Failed to fetch option data for live trading: #{e.message}" unless @mode == :paper

        puts "Warning: CSV master lookup failed (#{e.message}), using mock data for paper trading"

        # Generate mock data for paper trading
        premium = get_option_premium(selected_strike, current_spot, signal)

        {
          strike: selected_strike,
          expiry: expiry,
          ce_security_id: "PAPER_CE_#{selected_strike}",
          pe_security_id: "PAPER_PE_#{selected_strike}",
          premium: premium
        }
      end
    end

    def select_strike_for_signal(atm, step, signal, current_spot)
      case signal
      when :buy_ce
        # For bullish signals, prefer ATM or ATM+1
        # If current spot is closer to ATM+1, use that
        atm_plus = atm + step
        if (current_spot - atm_plus).abs < (current_spot - atm).abs
          atm_plus
        else
          atm
        end
      when :buy_pe
        # For bearish signals, prefer ATM or ATM-1
        # If current spot is closer to ATM-1, use that
        atm_minus = atm - step
        if (current_spot - atm_minus).abs < (current_spot - atm).abs
          atm_minus
        else
          atm
        end
      else
        # Default to ATM
        atm
      end
    end

    def get_option_premium(strike, spot, signal)
      # Calculate theoretical premium based on moneyness
      # This is a simplified calculation for paper trading
      moneyness = case signal
                  when :buy_ce
                    (spot - strike) / spot
                  when :buy_pe
                    (strike - spot) / spot
                  else
                    0.0
                  end

      # Base premium calculation
      base_premium = spot * 0.02 # 2% of spot price as base

      # Adjust based on moneyness
      if moneyness > 0.01 # ITM
        base_premium * 1.5
      elsif moneyness > -0.01 # ATM
        base_premium
      else # OTM
        base_premium * 0.5
      end
    end

    def nearest_strike(spot, step) = ((spot / step.to_f).round * step).to_i

    def nearest_weekly(wday_target)
      now = Time.now
      d = (wday_target - now.wday) % 7
      d = 7 if d.zero? && now.hour >= 15
      (now + (d * 86_400)).strftime("%Y-%m-%d")
    end

    def fetch_first_expiry
      # First try to get expiry dates from CSV master data
      begin
        underlying_symbol = get_underlying_symbol
        expiries = @csv_master.get_expiry_dates(underlying_symbol)

        if expiries&.any?
          first_expiry = expiries.first
          puts "[EXPIRY] Using first expiry from CSV master: #{first_expiry}"
          return first_expiry
        end
      rescue StandardError => e
        puts "[DEBUG] CSV master method failed: #{e.message}"
      end

      # Fallback to calculated expiry if CSV master fails
      puts "[WARNING] No expiry dates found from CSV master, using fallback calculation"
      fallback_expiry
    end

    def fallback_expiry
      # Fallback to old calculation method if API fails
      wday_target = @cfg.fetch("expiry_wday")
      now = Time.now
      d = (wday_target - now.wday) % 7
      d = 7 if d.zero? && now.hour >= 15
      (now + (d * 86_400)).strftime("%Y-%m-%d")
    end

    def index_by(chain)
      h = {}
      chain.each do |row|
        strike = (row.respond_to?(:strike) ? row.strike : row[:strike]).to_i
        opt    = (row.respond_to?(:option_type) ? row.option_type : row[:option_type]).to_s.upcase.to_sym
        sid    = (row.respond_to?(:security_id) ? row.security_id : row[:security_id]).to_s
        h[[strike, opt]] = sid
      end
      h
    end

    def get_underlying_symbol
      # Map security IDs to underlying symbols
      # This is a simple mapping - in a real implementation, you might want to
      # fetch this from the CSV master data or configuration
      case @cfg.fetch("idx_sid")
      when "13"
        "NIFTY"
      when "25", "23"
        "BANKNIFTY"
      when "51"
        "SENSEX"
      else
        # Default fallback - you might want to make this configurable
        "NIFTY"
      end
    end
  end
end
