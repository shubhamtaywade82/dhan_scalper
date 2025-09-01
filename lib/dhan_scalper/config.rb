# frozen_string_literal: true

require "yaml"
module DhanScalper
  class Config
    DEFAULT = { "symbols" => ["NIFTY"], "global" => { "min_profit_target" => 1000.0, "max_day_loss" => 1500.0,
                                                      "charge_per_order" => 20.0, "decision_interval" => 10, "log_level" => "INFO", "tp_pct" => 0.35, "sl_pct" => 0.18, "trail_pct" => 0.12 },
                "SYMBOLS" => { "NIFTY" => { "idx_sid" => ENV.fetch("NIFTY_IDX_SID", "13"), "seg_idx" => "IDX_I", "seg_opt" => "NSE_FNO",
                                            "strike_step" => 50, "lot_size" => 75, "qty_multiplier" => 1, "expiry_wday" => 4 } } }.freeze

    def self.load(path: ENV["SCALPER_CONFIG"])
      cfg = DEFAULT.dup
      if path && File.exist?(path)
        yml = YAML.safe_load(File.read(path), permitted_classes: [], aliases: false) || {}
        cfg = DEFAULT.merge(yml) { |_, a, b| a.is_a?(Hash) ? a.merge(b || {}) : b || a }
      end
      cfg
    end
  end
end
