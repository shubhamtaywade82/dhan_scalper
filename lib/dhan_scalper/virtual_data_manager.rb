# frozen_string_literal: true

require "csv"
require "json"
require "fileutils"

module DhanScalper
  class VirtualDataManager
    def initialize(data_dir: "data", memory_only: false)
      @data_dir = data_dir
      @memory_only = memory_only
      @orders_file = File.join(@data_dir, "orders.csv")
      @positions_file = File.join(@data_dir, "positions.csv")
      @balance_file = File.join(@data_dir, "balance.json")

      # In-memory cache
      @orders_cache = []
      @positions_cache = []
      # Use config balance instead of hardcoded value
      starting_balance = load_config_balance
      @balance_cache = { available: starting_balance, used: 0.0, total: starting_balance }

      ensure_data_directory unless @memory_only
      load_existing_data unless @memory_only
    end

    # Orders management
    def add_order(order)
      order_data = {
        id: order.id,
        security_id: order.security_id,
        side: order.side,
        quantity: order.qty,
        avg_price: order.avg_price,
        timestamp: Time.now.iso8601,
        status: "COMPLETED"
      }

      @orders_cache << order_data
      save_orders_to_csv unless @memory_only
      order_data
    end

    def get_orders(limit: 100)
      @orders_cache.last(limit)
    end

    def get_order_by_id(order_id)
      @orders_cache.find { |o| o[:id] == order_id }
    end

    # Positions management
    def add_position(position)
      position_data = {
        symbol: position.symbol,
        security_id: position.security_id,
        side: position.side,
        entry_price: position.entry_price,
        quantity: position.quantity,
        current_price: position.current_price,
        pnl: position.pnl,
        timestamp: Time.now.iso8601
      }

      # Remove existing position for same security_id if exists
      @positions_cache.reject! { |p| p[:security_id] == position.security_id }
      @positions_cache << position_data
      save_positions_to_csv unless @memory_only
      position_data
    end

    def update_position(security_id, updates)
      position = @positions_cache.find { |p| p[:security_id] == security_id }
      return nil unless position

      updates.each { |key, value| position[key] = value }
      position[:timestamp] = Time.now.iso8601
      save_positions_to_csv unless @memory_only
      position
    end

    def remove_position(security_id)
      @positions_cache.reject! { |p| p[:security_id] == security_id }
      save_positions_to_csv unless @memory_only
    end

    def get_positions
      @positions_cache
    end

    def get_position_by_security_id(security_id)
      @positions_cache.find { |p| p[:security_id] == security_id }
    end

    # Balance management
    def update_balance(amount, type: :debit)
      case type
      when :debit
        @balance_cache[:available] -= amount
        @balance_cache[:used] += amount
      when :credit
        @balance_cache[:available] += amount
        @balance_cache[:used] -= amount
      end

      @balance_cache[:total] = @balance_cache[:available] + @balance_cache[:used]
      save_balance_to_json unless @memory_only
      @balance_cache
    end

    def get_balance
      @balance_cache
    end

    def set_initial_balance(amount)
      @balance_cache = { available: amount, used: 0.0, total: amount }
      save_balance_to_json unless @memory_only
      @balance_cache
    end

    private

    def ensure_data_directory
      FileUtils.mkdir_p(@data_dir)
    end

    def load_existing_data
      load_orders_from_csv
      load_positions_from_csv
      load_balance_from_json
    end

    def load_orders_from_csv
      return unless File.exist?(@orders_file)

      CSV.foreach(@orders_file, headers: true, header_converters: :symbol) do |row|
        @orders_cache << row.to_h
      end
    rescue StandardError => e
      puts "Warning: Could not load orders from CSV: #{e.message}"
    end

    def save_orders_to_csv
      return if @orders_cache.empty?

      CSV.open(@orders_file, "w") do |csv|
        csv << @orders_cache.first.keys
        @orders_cache.each { |order| csv << order.values }
      end
    rescue StandardError => e
      puts "Warning: Could not save orders to CSV: #{e.message}"
    end

    def load_positions_from_csv
      return unless File.exist?(@positions_file)

      CSV.foreach(@positions_file, headers: true, header_converters: :symbol) do |row|
        @positions_cache << row.to_h
      end
    rescue StandardError => e
      puts "Warning: Could not load positions from CSV: #{e.message}"
    end

    def save_positions_to_csv
      return if @positions_cache.empty?

      CSV.open(@positions_file, "w") do |csv|
        csv << @positions_cache.first.keys
        @positions_cache.each { |position| csv << position.values }
      end
    rescue StandardError => e
      puts "Warning: Could not save positions to CSV: #{e.message}"
    end

    def load_balance_from_json
      return unless File.exist?(@balance_file)

      @balance_cache = JSON.parse(File.read(@balance_file), symbolize_names: true)
    rescue StandardError => e
      puts "Warning: Could not load balance from JSON: #{e.message}"
    end

    def save_balance_to_json
      File.write(@balance_file, JSON.pretty_generate(@balance_cache))
    rescue StandardError => e
      puts "Warning: Could not save balance to JSON: #{e.message}"
    end

    # Load starting balance from config
    def load_config_balance
      require_relative "config"
      cfg = DhanScalper::Config.load
      cfg.dig("paper", "starting_balance") || 200_000.0
    rescue StandardError
      200_000.0 # fallback to default
    end
  end
end
