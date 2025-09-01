# lib/dhan_scalper/trader.rb
module DhanScalper
  class Trader
    Position = Struct.new(:side,:sid,:entry,:qty_lots,:best,:trail_anchor)
    attr_reader :symbol, :session_pnl

    def initialize(ws:, symbol:, cfg:, picker:, broker:, state:, charge_per_order:)
      @ws,@symbol,@cfg,@picker,@broker,@state,@charge = ws,symbol,cfg,picker,broker,state,charge_per_order
      @open=nil; @session_pnl=0.0
    end

    def subscribe!(ce_map, pe_map)
      @ws.subscribe_one(segment: @cfg["seg_idx"], security_id: @cfg["idx_sid"])
      (ce_map.values+pe_map.values).compact.uniq.each{ |sid| @ws.subscribe_one(segment: @cfg["seg_opt"], security_id: sid) }
    end

    def maybe_enter(direction, ce_map, pe_map)
      return if @open
      spot = TickCache.ltp(@cfg["seg_idx"], @cfg["idx_sid"])&.to_f; return unless spot
      atm = OptionPicker.new(@cfg).nearest_strike(spot, @cfg["strike_step"])
      sid = (direction==:long_ce ? ce_map[atm] : direction==:long_pe ? pe_map[atm] : nil); return unless sid
      qty_lots = @cfg["qty_multiplier"]; qty = @cfg["lot_size"] * qty_lots
      order = @broker.buy_market(segment: @cfg["seg_opt"], security_id: sid, quantity: qty)
      entry = order.avg_price.nonzero? || TickCache.ltp(@cfg["seg_opt"], sid)&.to_f || 0.0
      @open = Position.new(order.side, sid, entry, qty_lots, 0.0, entry)
      publish_open!
    end

    def manage_open(tp_pct:, sl_pct:, trail_pct:)
      return unless @open
      ltp = TickCache.ltp(@cfg["seg_opt"], @open.sid)&.to_f; return unless ltp && ltp.positive?
      net = PnL.net(entry: @open.entry, ltp: ltp, lot_size: @cfg["lot_size"], qty_lots: @open.qty_lots, charge_per_order: @charge)
      @open.best = [@open.best, net].max
      # trail
      if ltp >= @open.entry*(1.0+trail_pct)
        @open.trail_anchor = [@open.trail_anchor, ltp*(1.0-trail_pct/2)].compact.max
      end
      # exits
      return exit!("TP", ltp, net)     if ltp >= @open.entry*(1.0+tp_pct)
      return exit!("SL", ltp, net)     if ltp <= @open.entry*(1.0-sl_pct)
      return exit!("TRAIL", ltp, net)  if @open.trail_anchor && ltp <= @open.trail_anchor
      publish_open!(ltp: ltp, net: net)
    end

    def exit!(reason, ltp, net_preview)
      qty = @cfg["lot_size"] * @open.qty_lots
      @broker.sell_market(segment: @cfg["seg_opt"], security_id: @open.sid, quantity: qty)
      net = PnL.net(entry: @open.entry, ltp: ltp, lot_size: @cfg["lot_size"], qty_lots: @open.qty_lots, charge_per_order: @charge)
      @session_pnl += net
      publish_closed!(reason: reason, exit_price: ltp, net: net)
      @open=nil
      publish_open!
    end

    private
    def publish_open!(ltp: nil, net: nil)
      return unless @state
      arr = []
      if @open
        ltp ||= TickCache.ltp(@cfg["seg_opt"], @open.sid)&.to_f
        net ||= PnL.net(entry: @open.entry, ltp: ltp || @open.entry, lot_size: @cfg["lot_size"], qty_lots: @open.qty_lots, charge_per_order: @charge)
        arr << {symbol: @symbol, sid: @open.sid, side: @open.side, qty_lots: @open.qty_lots, entry: @open.entry, ltp: ltp, net: net, best: @open.best}
      end
      @state.replace_open!(arr)
    end

    def publish_closed!(reason:, exit_price:, net:)
      return unless @state
      @state.push_closed!(symbol: @symbol, side: @open.side, reason: reason, entry: @open.entry, exit_price: exit_price, net: net)
    end
  end
end
