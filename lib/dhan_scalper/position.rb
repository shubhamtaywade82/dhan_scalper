# frozen_string_literal: true

module DhanScalper
  class Position
    attr_accessor :symbol, :security_id, :side, :entry_price, :quantity, :current_price, :pnl

    def initialize(symbol: nil, security_id:, side:, entry_price:, quantity:, current_price: nil, pnl: 0.0)
      @symbol = symbol
      @security_id = security_id
      @side = side
      @entry_price = entry_price
      @quantity = quantity
      @current_price = current_price || entry_price
      @pnl = pnl
    end

    def update_price(new_price)
      @current_price = new_price
      calculate_pnl
    end

    def calculate_pnl
      case @side.upcase
      when "BUY"
        @pnl = (@current_price - @entry_price) * @quantity
      when "SELL"
        @pnl = (@entry_price - @current_price) * @quantity
      else
        @pnl = 0.0
      end
      @pnl
    end

    def to_h
      {
        symbol: @symbol,
        security_id: @security_id,
        side: @side,
        entry_price: @entry_price,
        quantity: @quantity,
        current_price: @current_price,
        pnl: @pnl
      }
    end

    def to_s
      "#{@side} #{@quantity} #{@symbol || @security_id} @ #{@entry_price} (Current: #{@current_price}, P&L: #{@pnl.round(2)})"
    end
  end
end
