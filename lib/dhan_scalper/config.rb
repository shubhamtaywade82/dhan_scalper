# frozen_string_literal: true

require "yaml"
module DhanScalper
  class Config
    DEFAULT = {
      "symbols" => ["NIFTY"],
      "global" => {
        "session_hours" => ["09:20", "15:25"],
        "min_profit_target" => 1000.0,
        "max_day_loss" => 1500.0,
        "charge_per_order" => 20.0,
        "allocation_pct" => 0.30,
        "slippage_buffer_pct" => 0.01,
        "max_lots_per_trade" => 10,
        "decision_interval" => 10,
        "decision_interval_sec" => nil,
        "risk_loop_interval_sec" => 1,
        "ohlc_poll_minutes" => 3,
        "log_throttle_sec" => 60,
        "redis_namespace" => "dhan_scalper:v1",
        "historical_stagger_sec" => 4,
        "log_level" => "INFO",
        "tp_pct" => 0.35,
        "sl_pct" => 0.18,
        "trail_pct" => 0.12,
        "min_premium_price" => 1.0,
        "log_status_every" => 60
      },
      "paper" => {
        "starting_balance" => 200_000.0
      },
      "SYMBOLS" => {
        "NIFTY" => {
          "idx_sid" => ENV.fetch("NIFTY_IDX_SID", "13"),
          "seg_idx" => "IDX_I",
          "seg_opt" => "NSE_FNO",
          "strike_step" => 50,
          "lot_size" => 75,
          "qty_multiplier" => 1,
          "expiry_wday" => 4 # Fallback only - API expiry dates are used primarily
        }
      }
    }.freeze

    def self.load(path: ENV["SCALPER_CONFIG"] || "config/scalper.yml")
      cfg = deep_dup(DEFAULT)

      if path && File.exist?(path)
        begin
          yml = YAML.safe_load_file(path, permitted_classes: [], aliases: false)
          yml = {} if yml.nil?
        rescue Psych::SyntaxError
          yml = {}
        end
        # If the file is empty or invalid ({}), keep defaults entirely
        cfg = deep_merge_defaults(cfg, yml) unless yml.empty?
      end

      # ENV overrides for index SID per symbol (e.g., NIFTY_IDX_SID)
      if cfg["SYMBOLS"].is_a?(Hash)
        cfg["SYMBOLS"].each do |sym_name, sym_cfg|
          next unless sym_cfg.is_a?(Hash)

          env_key = "#{sym_name}_IDX_SID"
          default_sid = sym_cfg["idx_sid"] || "13"
          begin
            sid = ENV.fetch(env_key, default_sid)
            sym_cfg["idx_sid"] = sid
          rescue KeyError
            # ignore
          end
        end
      end

      cfg
    end

    def self.deep_dup(obj)
      case obj
      when Hash
        obj.each_with_object({}) { |(k, v), h| h[k] = deep_dup(v) }
      when Array
        obj.map { |v| deep_dup(v) }
      else
        obj
      end
    end

    # Merge yml into defaults with special rules:
    # - If a hash key exists with an empty hash value, keep it empty (do not merge defaults)
    # - If a value inside a hash is nil, fallback to default
    # - Arrays: if provided (even empty), take as-is; if nil or missing, keep default
    def self.deep_merge_defaults(defaults, yml)
      return deep_dup(defaults) unless yml

      if defaults.is_a?(Hash) && yml.is_a?(Hash)
        # If yml is an explicitly empty hash, return empty (do not merge defaults)
        return {} if yml.empty?

        keys = (defaults.keys + yml.keys).uniq
        keys.each_with_object({}) do |key, acc|
          dv = defaults[key]
          yv = yml.key?(key) ? yml[key] : :__missing__

          acc[key] = if yv == :__missing__
                       deep_dup(dv)
                     else
                       case [dv, yv]
                       in [Hash, Hash]
                         # If provided empty hash, keep empty; else merge recursively
                         yv.empty? ? {} : deep_merge_defaults(dv, yv)
                       in [Array, Array]
                         yv # take as-is, even if empty
                       else
                         yv.nil? ? deep_dup(dv) : yv
                       end
                     end
        end
      else
        yml.nil? ? deep_dup(defaults) : yml
      end
    end
  end
end
