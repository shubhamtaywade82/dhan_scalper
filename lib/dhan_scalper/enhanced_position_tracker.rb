# frozen_string_literal: true

require "concurrent"
require "csv"
require "json"
require "fileutils"
require_relative "position"
require_relative "tick_cache"

module DhanScalper
  class EnhancedPositionTracker
    def initialize(mode: :paper, data_dir: "data", logger: nil)
      @mode = mode
      @data_dir = data_dir
      @logger = logger || Logger.new($stdout)
      @positions = Concurrent::Map.new
      @closed_positions = []
      @session_stats = {
        total_trades: 0,
        winning_trades: 0,
        losing_trades: 0,
        total_pnl: 0.0,
        max_drawdown: 0.0,
        max_profit: 0.0,
        session_start: Time.now,
      }

      ensure_data_directory
      load_existing_data
    end

    def add_position(symbol, option_type, strike, expiry, security_id, quantity, entry_price)
      position_key = generate_position_key(symbol, option_type, strike, expiry)

      position = Position.new(
        security_id: security_id,
        side: "BUY",
        entry_price: entry_price,
        quantity: quantity,
        symbol: symbol,
        current_price: entry_price,
        option_type: option_type,
        strike: strike,
        expiry: expiry,
        timestamp: Time.now,
      )

      @positions[position_key] = position
      @session_stats[:total_trades] += 1

      @logger.info "[POSITION] Added: #{symbol} #{option_type} #{strike} #{expiry} " \
                   "#{quantity} lots @ ₹#{entry_price}"

      save_positions_to_csv
      position
    end

    def update_position(security_id, updates)
      position = find_position_by_security_id(security_id)
      return false unless position

      updates.each do |key, value|
        position.send("#{key}=", value) if position.respond_to?("#{key}=")
      end

      position.calculate_pnl
      save_positions_to_csv
      true
    end

    def close_position(security_id, exit_data)
      position = find_position_by_security_id(security_id)
      return false unless position

      position.close!(exit_data[:exit_price], exit_data[:exit_reason])

      # Move to closed positions
      position_key = find_position_key_by_security_id(security_id)
      @positions.delete(position_key)
      @closed_positions << position

      # Update session stats
      update_session_stats(position)

      @logger.info "[POSITION] Closed: #{position.symbol} #{position.option_type} " \
                   "#{position.strike} PnL: ₹#{position.pnl.round(2)} " \
                   "Reason: #{position.exit_reason}"

      save_positions_to_csv
      save_closed_positions_to_csv
      true
    end

    def get_positions
      @positions.values.map(&:to_h)
    end

    def get_open_positions
      @positions.values.select(&:open?).map(&:to_h)
    end

    def get_closed_positions
      @closed_positions.map(&:to_h)
    end

    def get_position_by_security_id(security_id)
      position = find_position_by_security_id(security_id)
      position&.to_h
    end

    def update_all_positions
      @positions.each_value do |position|
        current_price = get_current_price(position.security_id)
        position.update_price(current_price) if current_price&.positive?
      end
    end

    def get_total_pnl
      open_pnl = @positions.values.sum(&:pnl)
      closed_pnl = @closed_positions.sum(&:pnl)
      open_pnl + closed_pnl
    end

    def get_session_stats
      stats = @session_stats.dup
      stats[:total_pnl] = get_total_pnl
      stats[:open_positions] = @positions.size
      stats[:closed_positions] = @closed_positions.size
      stats[:session_duration] = Time.now - stats[:session_start]
      stats
    end

    def get_positions_summary
      open_positions = get_open_positions
      closed_positions = get_closed_positions

      {
        open: {
          count: open_positions.size,
          total_pnl: open_positions.sum { |p| p[:pnl] },
          positions: open_positions,
        },
        closed: {
          count: closed_positions.size,
          total_pnl: closed_positions.sum { |p| p[:pnl] },
          winning: closed_positions.count { |p| p[:pnl].positive? },
          losing: closed_positions.count { |p| p[:pnl].negative? },
          positions: closed_positions,
        },
        session: get_session_stats,
      }
    end

    private

    def generate_position_key(symbol, option_type, strike, expiry)
      "#{symbol}_#{option_type}_#{strike}_#{expiry}_#{Time.now.to_i}"
    end

    def find_position_by_security_id(security_id)
      @positions.values.find { |p| p.security_id == security_id }
    end

    def find_position_key_by_security_id(security_id)
      @positions.find { |_key, position| position.security_id == security_id }&.first
    end

    def get_current_price(security_id)
      TickCache.ltp("NSE_FNO", security_id)
    end

    def update_session_stats(position)
      pnl = position.pnl
      @session_stats[:total_pnl] += pnl

      if pnl.positive?
        @session_stats[:winning_trades] += 1
        @session_stats[:max_profit] = [@session_stats[:max_profit], pnl].max
      else
        @session_stats[:losing_trades] += 1
        @session_stats[:max_drawdown] = [@session_stats[:max_drawdown], pnl.abs].max
      end
    end

    def ensure_data_directory
      FileUtils.mkdir_p(@data_dir)
    end

    def load_existing_data
      load_positions_from_csv
      load_closed_positions_from_csv
    end

    def save_positions_to_csv
      return if @positions.empty?

      csv_file = File.join(@data_dir, "positions.csv")
      CSV.open(csv_file, "w") do |csv|
        csv << %w[symbol security_id side entry_price quantity current_price pnl pnl_percentage
                  option_type strike expiry timestamp]

        @positions.each_value do |position|
          csv << [
            position.symbol,
            position.security_id,
            position.side,
            position.entry_price,
            position.quantity,
            position.current_price,
            position.pnl,
            position.pnl_percentage,
            position.option_type,
            position.strike,
            position.expiry,
            position.timestamp,
          ]
        end
      end
    end

    def save_closed_positions_to_csv
      return if @closed_positions.empty?

      csv_file = File.join(@data_dir, "closed_positions.csv")
      CSV.open(csv_file, "w") do |csv|
        csv << %w[symbol security_id side entry_price quantity exit_price pnl pnl_percentage
                  option_type strike expiry entry_timestamp exit_timestamp exit_reason]

        @closed_positions.each do |position|
          csv << [
            position.symbol,
            position.security_id,
            position.side,
            position.entry_price,
            position.quantity,
            position.exit_price,
            position.pnl,
            position.pnl_percentage,
            position.option_type,
            position.strike,
            position.expiry,
            position.timestamp,
            position.exit_timestamp,
            position.exit_reason,
          ]
        end
      end
    end

    def load_positions_from_csv
      csv_file = File.join(@data_dir, "positions.csv")
      return unless File.exist?(csv_file)

      CSV.foreach(csv_file, headers: true) do |row|
        position = Position.new(
          security_id: row["security_id"],
          side: row["side"],
          entry_price: row["entry_price"].to_f,
          quantity: row["quantity"].to_i,
          symbol: row["symbol"],
          current_price: row["current_price"].to_f,
          pnl: row["pnl"].to_f,
          option_type: row["option_type"],
          strike: row["strike"]&.to_f,
          expiry: row["expiry"],
          timestamp: Time.parse(row["timestamp"]),
        )

        position_key = generate_position_key(
          position.symbol, position.option_type, position.strike, position.expiry
        )
        @positions[position_key] = position
      end

      @logger.info "[POSITION] Loaded #{@positions.size} existing positions"
    end

    def load_closed_positions_from_csv
      csv_file = File.join(@data_dir, "closed_positions.csv")
      return unless File.exist?(csv_file)

      CSV.foreach(csv_file, headers: true) do |row|
        position = Position.new(
          security_id: row["security_id"],
          side: row["side"],
          entry_price: row["entry_price"].to_f,
          quantity: row["quantity"].to_i,
          symbol: row["symbol"],
          current_price: row["exit_price"].to_f,
          pnl: row["pnl"].to_f,
          option_type: row["option_type"],
          strike: row["strike"]&.to_f,
          expiry: row["expiry"],
          timestamp: Time.parse(row["entry_timestamp"]),
        )

        position.exit_price = row["exit_price"].to_f
        position.exit_reason = row["exit_reason"]
        position.exit_timestamp = Time.parse(row["exit_timestamp"])

        @closed_positions << position
      end

      @logger.info "[POSITION] Loaded #{@closed_positions.size} closed positions"
    end
  end
end
