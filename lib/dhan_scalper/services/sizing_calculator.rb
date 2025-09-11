# frozen_string_literal: true

module DhanScalper
  module Services
    # Budget-based position sizing using allocation and slippage buffer.
    # Returns a hash { quantity: Integer, lots: Integer, reason: Symbol? }
    class SizingCalculator
      def initialize(config:, logger:)
        @config = config
        @logger = logger
      end

      # symbol: e.g., "NIFTY"; premium: option premium (Float); side: "BUY"/"SELL"
      def calculate(symbol:, premium:, side: "BUY")
        sym_cfg = @config.dig("SYMBOLS", symbol)
        return { quantity: 0, lots: 0, reason: :missing_symbol_config } unless sym_cfg

        lot_size = Integer(sym_cfg["lot_size"] || 50)
        allocation_pct = (@config.dig("global", "allocation_pct") || 0.1).to_f
        slippage_pct = (@config.dig("global", "slippage_buffer_pct") || 0.02).to_f
        available_funds = (@config.dig("global", "paper_wallet_rupees") || 200_000).to_f

        eff_price = premium * (1.0 + slippage_pct)
        per_lot_cost = eff_price * lot_size
        budget = available_funds * allocation_pct
        lots = (budget / per_lot_cost).floor

        if lots < 1
          @logger.info("[SIZER] Refusing entry: budget insufficient (budget=#{budget.round(2)}, per_lot=#{per_lot_cost.round(2)})")
          return { quantity: 0, lots: 0, reason: :insufficient_budget }
        end

        quantity = lots * lot_size
        { quantity: quantity, lots: lots, reason: :ok }
      rescue StandardError => e
        @logger.error("[SIZER] Error sizing #{symbol}: #{e.message}")
        { quantity: 0, lots: 0, reason: :error }
      end
    end
  end
end
