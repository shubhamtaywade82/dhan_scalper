# frozen_string_literal: true

require_relative "../order"

module DhanScalper
  module Services
    # OrderManager builds and executes orders across paper/live modes,
    # honoring dry-run via config and applying dedupe keys for idempotency.
    class OrderManager
      def initialize(config:, cache:, broker_paper:, broker_live:, logger:)
        @config = config
        @cache = cache
        @broker_paper = broker_paper
        @broker_live = broker_live
        @logger = logger
      end

      # data: { symbol:, security_id:, side:, quantity:, price:, order_type:, option_type:, strike: }
      # returns: { success: true, order_id:, order:, position:?, mode: }
      def place_order(data)
        mode = (@config["mode"] || "paper").to_s
        dry_run = !@config.fetch("place_order", false)
        dedupe_key = dedupe_key_for(data)

        if @cache.set_dedupe_key(dedupe_key, ttl: 10)
          @logger.info("[ORDER] #{mode.upcase} #{if dry_run
                                                   "(dry-run)"
                                                 end} #{data[:side]} #{data[:symbol]} #{data[:option_type]}@#{data[:strike]} qty=#{data[:quantity]}")
        else
          @logger.debug("[ORDER] DEDUPED #{data[:side]} #{data[:symbol]} key=#{dedupe_key}")
          return { success: false, error: :duplicate, mode: mode }
        end

        return simulate_order(data, mode: mode) if mode == "live" && dry_run

        case mode
        when "paper"
          execute_paper(data)
        when "live"
          execute_live(data)
        else
          { success: false, error: :invalid_mode }
        end
      rescue StandardError => e
        @logger.error("[ORDER] Error placing order: #{e.message}")
        { success: false, error: e.message }
      end

      private

      def execute_paper(data)
        res = @broker_paper.place_order(
          symbol: data[:symbol],
          instrument_id: data[:security_id],
          side: data[:side],
          quantity: data[:quantity],
          price: data[:price],
          order_type: data[:order_type],
        )
        res.merge(mode: :paper)
      end

      def execute_live(data)
        # Minimal pass-through to live broker adapter. The live broker class
        # should map to DhanHQ payloads and respect API nuances.
        res = @broker_live.place_order(
          symbol: data[:symbol],
          instrument_id: data[:security_id],
          side: data[:side],
          quantity: data[:quantity],
          price: data[:price],
          order_type: data[:order_type],
        )
        res.merge(mode: :live)
      end

      def simulate_order(data, mode:)
        # Log-only path; do not place with broker.
        order_id = "DRY-#{Time.now.to_f}"
        order = DhanScalper::Order.new(order_id, data[:security_id], data[:side], data[:quantity], data[:price])
        { success: true, order_id: order_id, order: order, position: nil, mode: mode }
      end

      def dedupe_key_for(data)
        parts = [data[:symbol], data[:security_id], data[:side], data[:quantity], data[:order_type]]
        "order:#{parts.join(":")}"
      end
    end
  end
end
