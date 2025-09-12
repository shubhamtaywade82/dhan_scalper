# frozen_string_literal: true

module DhanScalper
  class Position
    attr_accessor :symbol, :security_id, :side, :entry_price, :quantity, :current_price, :pnl, :option_type, :strike,
                  :expiry, :timestamp, :exit_price, :exit_reason, :exit_timestamp, :buy_avg, :buy_qty, :sell_avg, :sell_qty,
                  :net_qty, :realized_profit, :unrealized_profit, :multiplier, :lot_size, :strike_price, :expiry_date,
                  :underlying_symbol

    def initialize(security_id:, side:, entry_price:, quantity:, symbol: nil, current_price: nil, pnl: 0.0,
                   option_type: nil, strike: nil, expiry: nil, timestamp: nil, buy_avg: nil, buy_qty: nil,
                   sell_avg: 0.0, sell_qty: 0, net_qty: nil, realized_profit: 0.0, unrealized_profit: 0.0,
                   multiplier: 1, lot_size: 75, strike_price: nil, expiry_date: nil, underlying_symbol: nil)
      @symbol = symbol
      @security_id = security_id
      @side = side
      @entry_price = entry_price
      @quantity = quantity
      @current_price = current_price || entry_price
      @pnl = pnl
      @option_type = option_type
      @strike = strike
      @expiry = expiry
      @timestamp = timestamp || Time.now
      @exit_price = nil
      @exit_reason = nil
      @exit_timestamp = nil

      # Dhan-compatible fields
      @buy_avg = buy_avg || entry_price
      @buy_qty = buy_qty || quantity
      @sell_avg = sell_avg
      @sell_qty = sell_qty
      @net_qty = net_qty || quantity
      @realized_profit = realized_profit
      @unrealized_profit = unrealized_profit
      @multiplier = multiplier
      @lot_size = lot_size
      @strike_price = strike_price || strike
      @expiry_date = expiry_date || expiry
      @underlying_symbol = underlying_symbol
    end

    def update_price(new_price)
      @current_price = new_price
      calculate_pnl
    end

    def calculate_pnl
      @pnl = case @side.upcase
             when "BUY"
               (@current_price - @entry_price) * @quantity
             when "SELL"
               (@entry_price - @current_price) * @quantity
             else
               0.0
             end
      @unrealized_profit = @pnl
      @pnl
    end

    def pnl_percentage
      return 0.0 if @entry_price.zero?

      ((@current_price - @entry_price) / @entry_price) * 100
    end

    def closed?
      !@exit_price.nil?
    end

    def open?
      @exit_price.nil?
    end

    def close!(exit_price, reason)
      @exit_price = exit_price
      @exit_reason = reason
      @exit_timestamp = Time.now
      update_price(exit_price)
    end

    def to_h
      {
        symbol: @symbol,
        security_id: @security_id,
        side: @side,
        entry_price: @entry_price,
        quantity: @quantity,
        current_price: @current_price,
        pnl: @pnl,
        pnl_percentage: pnl_percentage,
        option_type: @option_type,
        strike: @strike,
        expiry: @expiry,
        timestamp: @timestamp,
        exit_price: @exit_price,
        exit_reason: @exit_reason,
        exit_timestamp: @exit_timestamp,
        closed: closed?,
        # Dhan-compatible fields
        buy_avg: @buy_avg,
        buy_qty: @buy_qty,
        sell_avg: @sell_avg,
        sell_qty: @sell_qty,
        net_qty: @net_qty,
        realized_profit: @realized_profit,
        unrealized_profit: @unrealized_profit,
        multiplier: @multiplier,
        lot_size: @lot_size,
        strike_price: @strike_price,
        expiry_date: @expiry_date,
        underlying_symbol: @underlying_symbol
      }
    end

    def to_s
      option_info = @option_type ? " #{@option_type} #{@strike}" : ""
      status = closed? ? "CLOSED" : "OPEN"
      exit_info = closed? ? " (Exit: #{@exit_price}, Reason: #{@exit_reason})" : ""

      "#{status}#{option_info}: #{@side} #{@quantity} #{@symbol || @security_id} @ #{@entry_price} " \
        "(Current: #{@current_price}, P&L: #{@pnl.round(2)}, #{pnl_percentage.round(1)}%)#{exit_info}"
    end
  end
end
