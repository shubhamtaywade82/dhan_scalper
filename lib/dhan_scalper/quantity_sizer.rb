# frozen_string_literal: true

module DhanScalper
  class QuantitySizer
    def initialize(cfg, balance_provider)
      @cfg = cfg
      @balance_provider = balance_provider
    end

    def calculate_lots(symbol, premium, side: 'BUY')
      return 0 unless premium&.positive?

      # Get configuration for this symbol
      symbol_cfg = @cfg.fetch('SYMBOLS').fetch(symbol)
      lot_size = symbol_cfg['lot_size']
      qty_multiplier = symbol_cfg['qty_multiplier']
      max_lots = @cfg.dig('global', 'max_lots_per_trade') || 10
      allocation_pct = @cfg.dig('global', 'allocation_pct') || 0.30
      slippage_buffer = @cfg.dig('global', 'slippage_buffer_pct') || 0.01

      # Get available balance
      balance = @balance_provider.available_balance
      return 0 unless balance&.positive?

      # Calculate allocation amount
      allocation_amount = balance * allocation_pct

      # Add slippage buffer to premium for conservative sizing
      adjusted_premium = premium * (1 + slippage_buffer)

      # Calculate lots based on allocation and premium
      lots = (allocation_amount / (adjusted_premium * lot_size)).floor

      # Apply constraints
      lots = [lots, max_lots].min
      lots = [lots, qty_multiplier].min
      lots = [lots, 0].max

      # Log sizing decision
      if lots.positive?
        puts "[#{symbol}] Sizing: Balance=₹#{balance.round(0)}, Allocation=₹#{allocation_amount.round(0)}, Premium=₹#{premium.round(2)}, Lots=#{lots}"
      else
        puts "[#{symbol}] Sizing: Insufficient balance or premium too high for position"
      end

      lots
    end

    def calculate_quantity(symbol, premium, side: 'BUY')
      lots = calculate_lots(symbol, premium, side: side)
      symbol_cfg = @cfg.fetch('SYMBOLS').fetch(symbol)
      lot_size = symbol_cfg['lot_size']

      lots * lot_size
    end

    def can_afford_position?(symbol, premium, side: 'BUY')
      calculate_lots(symbol, premium, side: side).positive?
    end
  end
end
