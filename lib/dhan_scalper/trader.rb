# frozen_string_literal: true

require "concurrent"

module DhanScalper
  module PnL
    module_function

    def round_trip_orders(charge_per_order) = 2 * charge_per_order

    def net(entry:, ltp:, lot_size:, qty_lots:, charge_per_order:)
      gross = (ltp - entry) * (lot_size * qty_lots)
      gross - round_trip_orders(charge_per_order)
    end
  end

  class Trend
    def initialize(seg_idx:, sid_idx:)
      @seg_idx = seg_idx
      @sid_idx = sid_idx
    end

    def decide
      # Load candle series for 1-minute and 3-minute intervals
      c1_series = CandleSeries.load_from_dhan_intraday(
        seg: @seg_idx,
        sid: @sid_idx,
        interval: "1", 
        symbol: "INDEX"
      )
      c3_series = CandleSeries.load_from_dhan_intraday(
        seg: @seg_idx,
        sid: @sid_idx,
        interval: "3",
        symbol: "INDEX"
      )
      
      return :none if c1_series.candles.size < 50 || c3_series.candles.size < 50

      # Use built-in CandleSeries indicators instead of external Indicators
      e1f = c1_series.ema(20).last
      e1s = c1_series.ema(50).last
      r1 = c1_series.rsi(14).last
      e3f = c3_series.ema(20).last
      e3s = c3_series.ema(50).last
      r3 = c3_series.rsi(14).last
      
      up   = e1f > e1s && r1 > 55 && e3f > e3s && r3 > 52
      down = e1f < e1s && r1 < 45 && e3f < e3s && r3 < 48
      return :long_ce if up
      return :long_pe if down

      :none
    end
  end

  class Trader
    Position = Struct.new(:side, :sid, :entry, :qty_lots, :order_id, :best, :trail_anchor)

    attr_reader :symbol, :session_pnl

    def initialize(ws:, symbol:, cfg:, picker:, gl:, state: nil, quantity_sizer: nil)
      @ws = ws
      @symbol = symbol
      @cfg = cfg
      @picker = picker
      @gl = gl
      @state = state
      @quantity_sizer = quantity_sizer
      @open = nil
      @session_pnl = 0.0
      @killed = false
      subscribe_index
    end

    def subscribe_index
      @ws.subscribe_one(segment: @cfg["seg_idx"], security_id: @cfg["idx_sid"])
    end

    def subscribe_options(ce_map, pe_map)
      (ce_map.values + pe_map.values).compact.uniq.each do |sid|
        @ws.subscribe_one(segment: @cfg["seg_opt"], security_id: sid)
      end
    end

    def can_trade? = !@killed && @open.nil?

    def maybe_enter(direction, ce_map, pe_map)
      return unless can_trade?

      spot = TickCache.ltp(@cfg["seg_idx"], @cfg["idx_sid"])&.to_f
      return unless spot

      atm = @picker.nearest_strike(spot, @cfg["strike_step"])
      sid = (if direction == :long_ce
               ce_map[atm]
             else
               direction == :long_pe ? pe_map[atm] : nil
             end)
      return unless sid

      ltp = TickCache.ltp(@cfg["seg_opt"], sid)&.to_f
      return unless ltp&.positive?

      # Use QuantitySizer for allocation-based sizing
      if @quantity_sizer
        qty_lots = @quantity_sizer.calculate_lots(@symbol, ltp)
        return unless qty_lots > 0
        qty = @cfg["lot_size"] * qty_lots
      else
        # Fallback to old fixed sizing
        qty_lots = @cfg["qty_multiplier"]
        qty = @cfg["lot_size"] * qty_lots
      end

      # Get broker from global context
      broker = @gl.instance_variable_get(:@broker)
      return unless broker

      # Place order through broker
      order = broker.buy_market(
        segment: @cfg["seg_opt"],
        security_id: sid,
        quantity: qty
      )

      return puts("[#{@symbol}] ORDER FAIL: Could not place order") unless order

      entry = TickCache.ltp(@cfg["seg_opt"], sid)&.to_f || ltp
      side  = (direction == :long_ce ? "BUY_CE" : "BUY_PE")
      @open = Position.new(side, sid, entry, qty_lots, order.id, 0.0, entry)
      puts "[#{@symbol}] ENTRY #{side} sid=#{sid} entry≈#{entry.round(2)} lots=#{qty_lots}"
      publish_open_snapshot!
    end

    def manage_open(tp_pct:, sl_pct:, trail_pct:, charge_per_order:)
      return unless @open

      ltp = TickCache.ltp(@cfg["seg_opt"], @open.sid)&.to_f
      return unless ltp&.positive?

      net = PnL.net(entry: @open.entry, ltp: ltp, lot_size: @cfg["lot_size"], qty_lots: @open.qty_lots,
                    charge_per_order: charge_per_order)
      @open.best = [@open.best, net].max

      trail_trig = @open.entry * (1.0 + trail_pct)
      @open.trail_anchor = [@open.trail_anchor, ltp * (1.0 - trail_pct / 2)].compact.max if ltp >= trail_trig

      if ltp >= @open.entry * (1.0 + tp_pct) || (@gl.session_pnl_preview(self, net) >= @gl.session_target)
        return close!("TP", ltp, charge_per_order)
      end
      return close!("SL", ltp, charge_per_order) if ltp <= @open.entry * (1.0 - sl_pct)
      return close!("TRAIL", ltp, charge_per_order) if @open.trail_anchor && ltp <= @open.trail_anchor
      return close!("TECH_INVALID", ltp, charge_per_order) if opposite_signal?

      print "\r[#{@symbol}] OPEN side=#{@open.side} ltp=#{ltp.round(2)} net=#{net.round(0)} best=#{@open.best.round(0)} session=#{@session_pnl.round(0)}"
      publish_open_snapshot!
    end

    def close!(reason, ltp, charge_per_order)
      qty = @cfg["lot_size"] * @open.qty_lots

      # Get broker from global context
      broker = @gl.instance_variable_get(:@broker)
      return puts("[#{@symbol}] EXIT FAIL: No broker available") unless broker

      # Place sell order through broker
      sell_order = broker.sell_market(
        segment: @cfg["seg_opt"],
        security_id: @open.sid,
        quantity: qty
      )

      return puts("[#{@symbol}] EXIT FAIL: Could not place sell order") unless sell_order

      net = PnL.net(entry: @open.entry, ltp: ltp, lot_size: @cfg["lot_size"], qty_lots: @open.qty_lots,
                    charge_per_order: charge_per_order)
      @session_pnl += net
      puts "\n[#{@symbol}] EXIT #{reason} sid=#{@open.sid} ltp≈#{ltp.round(2)} net=#{net.round(0)} session=#{@session_pnl.round(0)}"
      publish_closed!(reason: reason, exit_price: ltp, net: net)
      @open = nil
      publish_open_snapshot!
    end

    def kill! = @killed = true

    # ------------- state publishing -------------
    def publish_open_snapshot!
      return unless @state

      arr = []
      if @open
        ltp = DhanScalper::TickCache.ltp(@cfg["seg_opt"], @open.sid)&.to_f
        charge_per_order = begin
          @gl.instance_variable_get(:@cfg).dig("global", "charge_per_order").to_f
        rescue StandardError
          20.0
        end
        net = DhanScalper::PnL.net(entry: @open.entry, ltp: ltp || @open.entry,
                                   lot_size: @cfg["lot_size"], qty_lots: @open.qty_lots,
                                   charge_per_order: charge_per_order)
        arr << {
          symbol: @symbol, sid: @open.sid, side: @open.side,
          qty_lots: @open.qty_lots, entry: @open.entry, ltp: ltp, net: net, best: @open.best
        }
      end
      @state.replace_open!(arr)
    end

    def publish_closed!(reason:, exit_price:, net:)
      return unless @state

      @state.push_closed!(
        symbol: @symbol, side: @open.side, reason: reason,
        entry: @open.entry, exit_price: exit_price, net: net
      )
    end

    private

    def opposite_signal?
      dir = Trend.new(seg_idx: @cfg["seg_idx"], sid_idx: @cfg["idx_sid"]).decide
      (@open.side == "BUY_CE" && dir == :long_pe) || (@open.side == "BUY_PE" && dir == :long_ce)
    rescue StandardError; false
    end
  end
end
