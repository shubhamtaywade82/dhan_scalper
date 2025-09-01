# frozen_string_literal: true

require "concurrent"

module DhanScalper
  class State
    # :status => :running | :paused | :stopped
    attr_reader :status, :session_target, :max_day_loss, :symbols, :open, :closed,
                :subs_idx, :subs_opt, :session_pnl

    def initialize(symbols:, session_target:, max_day_loss:)
      @status         = Concurrent::AtomicReference.new(:running)
      @session_target = session_target
      @max_day_loss   = max_day_loss
      @symbols        = Concurrent::Array.new(symbols)
      @session_pnl    = Concurrent::AtomicFloat.new(0.0)

      @open   = Concurrent::Array.new        # [{symbol:, sid:, side:, entry:, qty_lots:, ltp:, net:, best:}]
      @closed = Concurrent::Array.new        # same hash + {:reason, :exit_price, :net}
      @subs_idx = Concurrent::Array.new      # [{segment:, security_id:, symbol:, ltp:, ts:}]
      @subs_opt = Concurrent::Array.new      # ditto for options
      @subs_key = Concurrent::Map.new        # key -> index in arrays (for fast upserts)
    end

    def set_status(v) = @status.set(v)
    def status        = @status.get

    def set_session_pnl(v) = @session_pnl.value = v
    def add_session_pnl(d) = @session_pnl.update { |x| x + d }
    def pnl               = @session_pnl.value

    # -------- subscriptions upsert ----------
    def upsert_sub(sub_list, key_map, rec)
      key = "#{rec[:segment]}:#{rec[:security_id]}"
      if (idx = key_map[key])
        sub_list[idx] = rec
      else
        key_map[key] = sub_list.length
        sub_list << rec
      end
    end

    def upsert_idx_sub(rec)  = upsert_sub(@subs_idx, @subs_key, rec)
    def upsert_opt_sub(rec)  = upsert_sub(@subs_opt, @subs_key, rec)

    # -------- open/closed positions ----------
    def replace_open!(arr)  # whole replacement from Trader snapshot
      @open.clear
      arr.each { |h| @open << h }
    end

    def push_closed!(h)
      @closed << h
      @closed.shift while @closed.size > 30 # limit history
    end
  end
end
