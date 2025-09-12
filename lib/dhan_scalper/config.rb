# frozen_string_literal: true

require "yaml"
require_relative "support/money"

module DhanScalper
  class Config
    class ValidationError < StandardError; end
    DEFAULT = {
      symbols: ["NIFTY"],
      global: {
        session_hours: ["09:20", "15:25"],
        min_profit_target: 1_000.0,
        max_day_loss: 1_500.0,
        charge_per_order: 20.0,
        allocation_pct: 0.30,
        slippage_buffer_pct: 0.01,
        max_lots_per_trade: 10,
        decision_interval: 10,
        decision_interval_sec: nil,
        risk_loop_interval_sec: 1,
        ohlc_poll_minutes: 3,
        log_throttle_sec: 60,
        redis_namespace: "dhan_scalper:v1",
        historical_stagger_sec: 4,
        log_level: "INFO",
        tp_pct: 0.35,
        sl_pct: 0.18,
        trail_pct: 0.12,
        min_premium_price: 1.0,
        log_status_every: 60,
        # Risk manager hardening
        time_stop_seconds: 300, # 5 minutes default
        max_daily_loss_rs: 2_000.0, # Max daily loss in rupees
        cooldown_after_loss_seconds: 180, # 3 minutes default
        enable_time_stop: true,
        enable_daily_loss_cap: true,
        enable_cooldown: true,
      },
      paper: {
        starting_balance: 200_000.0,
      },
      SYMBOLS: {
        NIFTY: {
          idx_sid: ENV.fetch("NIFTY_IDX_SID", "13"),
          seg_idx: "IDX_I",
          seg_opt: "NSE_FNO",
          strike_step: 50,
          lot_size: 75,
          qty_multiplier: 1,
          expiry_wday: 4, # Fallback only - API expiry dates are used primarily
        },
      },
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

      # Validate the loaded configuration
      validate_config!(cfg)

      cfg
    end

    # Validate configuration and raise ValidationError if invalid
    def self.validate_config!(config)
      errors = []

      # Validate fee_per_order_rs
      fee = config.dig("global", "charge_per_order")
      if fee.nil? || !fee.is_a?(Numeric) || fee <= 0
        errors << "Invalid fee_per_order_rs: must be a positive number, got #{fee.inspect}"
      end

      # Validate starting_balance
      balance = config.dig("paper", "starting_balance")
      if balance.nil? || !balance.is_a?(Numeric) || balance <= 0
        errors << "Invalid starting_balance: must be a positive number, got #{balance.inspect}"
      end

      # Validate trading windows (session_hours)
      session_hours = config.dig("global", "session_hours")
      if session_hours.nil? || !session_hours.is_a?(Array) || session_hours.length != 2
        errors << "Invalid session_hours: must be an array with 2 time strings, got #{session_hours.inspect}"
      elsif session_hours.any? { |h| !h.is_a?(String) || !h.match?(/\A\d{2}:\d{2}\z/) }
        errors << "Invalid session_hours format: must be in HH:MM format, got #{session_hours.inspect}"
      end

      # Validate trading window times are logical
      if session_hours.is_a?(Array) && session_hours.length == 2
        begin
          start_time = Time.parse(session_hours[0])
          end_time = Time.parse(session_hours[1])
          if start_time >= end_time
            errors << "Invalid session_hours: start time must be before end time, got #{session_hours.inspect}"
          end
        rescue ArgumentError
          errors << "Invalid session_hours: unable to parse time format, got #{session_hours.inspect}"
        end
      end

      # Validate symbols array
      symbols = config["symbols"]
      if symbols.nil? || !symbols.is_a?(Array) || symbols.empty?
        errors << "Invalid symbols: must be a non-empty array, got #{symbols.inspect}"
      end

      # Validate SYMBOLS configuration for each symbol
      if symbols.is_a?(Array)
        symbols.each do |symbol|
          symbol_config = config.dig("SYMBOLS", symbol)
          if symbol_config.nil? || !symbol_config.is_a?(Hash)
            errors << "Missing or invalid SYMBOLS configuration for #{symbol}"
          else
            # Validate required symbol fields
            required_fields = %w[idx_sid seg_idx seg_opt strike_step lot_size]
            required_fields.each do |field|
              errors << "Missing required field '#{field}' for symbol #{symbol}" if symbol_config[field].nil?
            end

            # Validate lot_size is positive
            lot_size = symbol_config["lot_size"]
            if lot_size && (!lot_size.is_a?(Numeric) || lot_size <= 0)
              errors << "Invalid lot_size for #{symbol}: must be a positive number, got #{lot_size.inspect}"
            end
          end
        end
      end

      # Validate risk manager settings
      validate_risk_manager_config!(config, errors)

      # Raise validation error if any issues found
      return unless errors.any?

      raise ValidationError, "Configuration validation failed:\n" + errors.map { |e| "  - #{e}" }.join("\n")
    end

    # Validate risk manager configuration
    def self.validate_risk_manager_config!(config, errors)
      global = config["global"] || {}

      # Validate time stop settings
      if global["enable_time_stop"]
        time_stop = global["time_stop_seconds"]
        if time_stop.nil? || !time_stop.is_a?(Numeric) || time_stop <= 0
          errors << "Invalid time_stop_seconds: must be a positive number, got #{time_stop.inspect}"
        end
      end

      # Validate daily loss cap settings
      if global["enable_daily_loss_cap"]
        max_loss = global["max_daily_loss_rs"]
        if max_loss.nil? || !max_loss.is_a?(Numeric) || max_loss <= 0
          errors << "Invalid max_daily_loss_rs: must be a positive number, got #{max_loss.inspect}"
        end
      end

      # Validate cooldown settings
      if global["enable_cooldown"]
        cooldown = global["cooldown_after_loss_seconds"]
        if cooldown.nil? || !cooldown.is_a?(Numeric) || cooldown <= 0
          errors << "Invalid cooldown_after_loss_seconds: must be a positive number, got #{cooldown.inspect}"
        end
      end

      # Validate boolean flags
      boolean_flags = %w[enable_time_stop enable_daily_loss_cap enable_cooldown]
      boolean_flags.each do |flag|
        value = global[flag]
        if !value.nil? && !value.is_a?(TrueClass) && !value.is_a?(FalseClass)
          errors << "Invalid #{flag}: must be true or false, got #{value.inspect}"
        end
      end
    end

    # Expose commonly used configuration values
    def self.fee
      @fee ||= DhanScalper::Support::Money.bd(load.dig("global", "charge_per_order") || 20.0)
    end

    def self.paper_start_balance
      @paper_start_balance ||= DhanScalper::Support::Money.bd(load.dig("paper", "starting_balance") || 200_000.0)
    end

    def self.trading_session_hours
      @trading_session_hours ||= load.dig("global", "session_hours") || ["09:20", "15:25"]
    end

    def self.symbols
      @symbols ||= load["symbols"] || ["NIFTY"]
    end

    def self.symbol_config(symbol)
      load.dig("SYMBOLS", symbol) || {}
    end

    def self.global_config
      @global_config ||= load["global"] || {}
    end

    def self.paper_config
      @paper_config ||= load["paper"] || {}
    end

    # Reset cached values (useful for testing)
    def self.reset_cache!
      @fee = nil
      @paper_start_balance = nil
      @trading_session_hours = nil
      @symbols = nil
      @global_config = nil
      @paper_config = nil
    end

    def self.deep_dup(obj)
      case obj
      when Hash
        obj.transform_values { |v| deep_dup(v) }
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
