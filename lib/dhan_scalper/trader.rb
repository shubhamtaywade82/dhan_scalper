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
      # Load candle series for 1-minute and 5-minute intervals
      c1_series = CandleSeries.load_from_dhan_intraday(
        seg: @seg_idx,
        sid: @sid_idx,
        interval: "1",
        symbol: "INDEX"
      )
      c5_series = CandleSeries.load_from_dhan_intraday(
        seg: @seg_idx,
        sid: @sid_idx,
        interval: "5",
        symbol: "INDEX"
      )
      return :none if c1_series.nil? || c5_series.nil?
      return :none if c1_series.candles.size < 50 || c5_series.candles.size < 50

      # Primary: Supertrend across 1m and 5m
      begin
        st1 = DhanScalper::Indicators::Supertrend.new(series: c1_series).call
        st5 = DhanScalper::Indicators::Supertrend.new(series: c5_series).call

        if st1&.any? && st5&.any?
          last_close_1 = c1_series.closes.last.to_f
          last_close_5 = c5_series.closes.last.to_f
          last_st_1 = st1.compact.last
          last_st_5 = st5.compact.last

          if last_st_1 && last_st_5
            puts "[DEBUG] Supertrend 1m: st=#{last_st_1.round(2)} close=#{last_close_1.round(2)}"
            puts "[DEBUG] Supertrend 5m: st=#{last_st_5.round(2)} close=#{last_close_5.round(2)}"

            up   = (last_close_1 > last_st_1) && (last_close_5 > last_st_5)
            down = (last_close_1 < last_st_1) && (last_close_5 < last_st_5)
            return :long_ce if up
            return :long_pe if down
          end
        end
      rescue StandardError
        # Fall through to EMA/RSI logic
      end

      # Fallback: EMA/RSI when supertrend unavailable
      e1f = c1_series.ema(20).last
      e1s = c1_series.ema(50).last
      r1 = c1_series.rsi(14).last
      e5f = c5_series.ema(20).last
      e5s = c5_series.ema(50).last
      r5 = c5_series.rsi(14).last

      up   = e1f > e1s && r1 > 55 && e5f > e5s && r5 > 52
      down = e1f < e1s && r1 < 45 && e5f < e5s && r5 < 48
      return :long_ce if up
      return :long_pe if down

      :none
    end
  end

  class Trader
    Position = Struct.new(:side, :sid, :entry, :qty_lots, :order_id, :best, :trail_anchor)

    attr_reader :symbol, :session_pnl

    def initialize(ws:, symbol:, cfg:, picker:, gl:, state: nil, quantity_sizer: nil, enhanced: true)
      @ws = ws
      @symbol = symbol
      @cfg = cfg
      @picker = picker
      @gl = gl
      @enhanced = enhanced
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

      # Check minimum premium price
      min_premium = @gl.instance_variable_get(:@cfg)&.dig("global", "min_premium_price") || 1.0
      if ltp < min_premium
        puts "[#{@symbol}] SKIP: Premium too low (#{ltp.round(2)} < #{min_premium})"
        return
      end

      # Use QuantitySizer for allocation-based sizing
      if @quantity_sizer
        qty_lots = @quantity_sizer.calculate_lots(@symbol, ltp)
        return unless qty_lots.positive?

      else
        # Fallback to old fixed sizing
        qty_lots = @cfg["qty_multiplier"]
      end
      qty = @cfg["lot_size"] * qty_lots

      # Get broker from global context
      broker = @gl.instance_variable_get(:@broker)
      return unless broker

      # Get charge per order from global config
      charge_per_order = @gl.instance_variable_get(:@cfg)&.dig("global", "charge_per_order") || 20

      # Place order through broker
      order = broker.buy_market(
        segment: @cfg["seg_opt"],
        security_id: sid,
        quantity: qty,
        charge_per_order: charge_per_order
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
      @open.trail_anchor = [@open.trail_anchor, ltp * (1.0 - (trail_pct / 2))].compact.max if ltp >= trail_trig

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
        quantity: qty,
        charge_per_order: charge_per_order
      )

      return puts("[#{@symbol}] EXIT FAIL: Could not place sell order") unless sell_order

      net = PnL.net(entry: @open.entry, ltp: ltp, lot_size: @cfg["lot_size"], qty_lots: @open.qty_lots,
                    charge_per_order: charge_per_order)
      @session_pnl += net

      # Update balance provider with realized PnL
      balance_provider = @gl.instance_variable_get(:@balance_provider)
      balance_provider&.add_realized_pnl(net)

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
      trend_class = @enhanced ? DhanScalper::TrendEnhanced : DhanScalper::Trend
      dir = trend_class.new(seg_idx: @cfg["seg_idx"], sid_idx: @cfg["idx_sid"]).decide
      (@open.side == "BUY_CE" && dir == :long_pe) || (@open.side == "BUY_PE" && dir == :long_ce)
    rescue StandardError; false
    end
  end
end
