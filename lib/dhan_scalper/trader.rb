# frozen_string_literal: true

require "concurrent"

module DhanScalper
  class TickCache
    MAP = Concurrent::Map.new
    def self.put(t) = MAP["#{t[:segment]}:#{t[:security_id]}"]=t
    def self.ltp(seg, sid) = MAP["#{seg}:#{sid}"]&.dig(:ltp)
  end

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
      @seg_idx, @sid_idx = seg_idx, sid_idx
    end

    def decide
      c1 = Bars.c1(seg: @seg_idx, sid: @sid_idx)
      c3 = Bars.c3(seg: @seg_idx, sid: @sid_idx)
      return :none if c1.size < 50 || c3.size < 50
      e1f = Indicators.ema_last(c1, 20); e1s = Indicators.ema_last(c1, 50); r1=Indicators.rsi_last(c1,14)
      e3f = Indicators.ema_last(c3, 20); e3s = Indicators.ema_last(c3, 50); r3=Indicators.rsi_last(c3,14)
      up   = (e1f>e1s && r1>55) && (e3f>e3s && r3>52)
      down = (e1f<e1s && r1<45) && (e3f<e3s && r3<48)
      return :long_ce if up
      return :long_pe if down
      :none
    end
  end

  class Trader
    Position = Struct.new(:side,:sid,:entry,:qty_lots,:order_id,:best,:trail_anchor)

    attr_reader :symbol, :session_pnl

    def initialize(ws:, symbol:, cfg:, picker:, gl:, state: nil)
      @ws,@symbol,@cfg,@picker,@gl,@state = ws,symbol,cfg,picker,gl,state
      @open=nil; @session_pnl=0.0; @killed=false
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
      sid = (direction == :long_ce ? ce_map[atm] : direction == :long_pe ? pe_map[atm] : nil)
      return unless sid
      ltp = TickCache.ltp(@cfg["seg_opt"], sid)&.to_f
      return unless ltp && ltp.positive?

      qty_lots = @cfg["qty_multiplier"]
      qty = @cfg["lot_size"] * qty_lots

      order = DhanHQ::Models::Order.new(
        transaction_type: "BUY",
        exchange_segment: @cfg["seg_opt"],
        product_type: "MARGIN",
        order_type: "MARKET",
        validity: "DAY",
        security_id: sid,
        quantity: qty
      )
      order.save
      return puts("[#{@symbol}] ORDER FAIL: #{order.errors.full_messages.join(", ")}") unless order.persisted?

      entry = TickCache.ltp(@cfg["seg_opt"], sid)&.to_f || ltp
      side  = (direction==:long_ce ? "BUY_CE" : "BUY_PE")
      @open = Position.new(side,sid,entry,qty_lots,order.order_id,0.0,entry)
      puts "[#{@symbol}] ENTRY #{side} sid=#{sid} entry≈#{entry.round(2)}"
      publish_open_snapshot!
    end

    def manage_open(tp_pct:, sl_pct:, trail_pct:, charge_per_order:)
      return unless @open
      ltp = TickCache.ltp(@cfg["seg_opt"], @open.sid)&.to_f
      return unless ltp && ltp.positive?

      net = PnL.net(entry: @open.entry, ltp: ltp, lot_size: @cfg["lot_size"], qty_lots: @open.qty_lots, charge_per_order: charge_per_order)
      @open.best = [@open.best, net].max

      trail_trig = @open.entry * (1.0 + trail_pct)
      @open.trail_anchor = [@open.trail_anchor, ltp * (1.0 - trail_pct/2)].compact.max if ltp >= trail_trig

      if ltp >= @open.entry*(1.0 + tp_pct) || (@gl.session_pnl_preview(self, net) >= @gl.session_target)
        return close!("TP", ltp, charge_per_order)
      end
      return close!("SL", ltp, charge_per_order) if ltp <= @open.entry*(1.0 - sl_pct)
      return close!("TRAIL", ltp, charge_per_order) if @open.trail_anchor && ltp <= @open.trail_anchor
      return close!("TECH_INVALID", ltp, charge_per_order) if opposite_signal?

      print "\r[#{@symbol}] OPEN side=#{@open.side} ltp=#{ltp.round(2)} net=#{net.round(0)} best=#{@open.best.round(0)} session=#{@session_pnl.round(0)}"
      publish_open_snapshot!
    end

    def close!(reason, ltp, charge_per_order)
      qty = @cfg["lot_size"] * @open.qty_lots
      sell = DhanHQ::Models::Order.new(
        transaction_type: "SELL",
        exchange_segment: @cfg["seg_opt"],
        product_type: "MARGIN",
        order_type: "MARKET",
        validity: "DAY",
        security_id: @open.sid,
        quantity: qty
      )
      sell.save
      net = PnL.net(entry: @open.entry, ltp: ltp, lot_size: @cfg["lot_size"], qty_lots: @open.qty_lots, charge_per_order: charge_per_order)
      @session_pnl += net
      puts "\n[#{@symbol}] EXIT #{reason} sid=#{@open.sid} ltp≈#{ltp.round(2)} net=#{net.round(0)} session=#{@session_pnl.round(0)}"
      publish_closed!(reason: reason, exit_price: ltp, net: net)
      @open=nil
      publish_open_snapshot!
    end

    def kill!; @killed=true; end

    # ------------- state publishing -------------
    def publish_open_snapshot!
      return unless @state
      arr = []
      if @open
        ltp = DhanScalper::Trader::TickCache.ltp(@cfg["seg_opt"], @open.sid)&.to_f
        charge_per_order = begin
          @gl.instance_variable_get(:@cfg).dig("global","charge_per_order").to_f
        rescue
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
      (@open.side=="BUY_CE" && dir==:long_pe) || (@open.side=="BUY_PE" && dir==:long_ce)
    rescue; false; end
  end
end