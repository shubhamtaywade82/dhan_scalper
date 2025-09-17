# frozen_string_literal: true

module DhanScalper
  module Services
    # Manages trading session state and data
    class SessionManager
      attr_reader :session_data, :cached_trends, :cached_pickers, :security_to_strike

      def initialize(session_reporter:, logger:)
        @session_reporter = session_reporter
        @logger = logger

        # Initialize session data
        @session_data = {
          session_id: nil,
          start_time: nil,
          end_time: nil,
          total_trades: 0,
          successful_trades: 0,
          failed_trades: 0,
          trades: [],
          max_pnl: 0.0,
          min_pnl: 0.0,
          symbols_traded: Set.new
        }

        # Cache for trend objects and option pickers
        @cached_trends = {}
        @cached_pickers = {}

        # Cache for security ID to strike mapping
        @security_to_strike = {}
      end

      def load_or_create_session(mode:, starting_balance:)
        @session_data = @session_reporter.load_or_create_session(
          mode: mode,
          starting_balance: starting_balance
        )
      end

      def update_session_data_with_current_state(position_tracker, balance_provider)
        current_time = Time.now
        positions_summary = position_tracker.get_positions_summary

        @session_data.merge!(
          end_time: current_time,
          total_pnl: positions_summary[:total_pnl] || 0.0,
          max_pnl: [@session_data[:max_pnl], positions_summary[:total_pnl] || 0.0].max,
          min_pnl: [@session_data[:min_pnl], positions_summary[:total_pnl] || 0.0].min
        )
      end

      def add_trade(trade_data)
        @session_data[:trades] << trade_data
        @session_data[:total_trades] += 1
        @session_data[:symbols_traded].add(trade_data[:symbol]) if trade_data[:symbol]
      end

      def increment_successful_trades
        @session_data[:successful_trades] += 1
      end

      def increment_failed_trades
        @session_data[:failed_trades] += 1
      end

      def get_cached_trend(symbol, symbol_config)
        trend_key = "#{symbol}_#{symbol_config['seg_idx']}_#{symbol_config['idx_sid']}"
        @cached_trends[trend_key] ||= begin
          trend = DhanScalper::TrendEnhanced.new(
            seg_idx: symbol_config['seg_idx'],
            sid_idx: symbol_config['idx_sid']
          )
          @cached_trends[trend_key] = trend
        end
      end

      def get_cached_picker(symbol, symbol_config)
        picker_key = "#{symbol}_#{symbol_config['seg_idx']}_#{symbol_config['idx_sid']}"
        @cached_pickers[picker_key] ||= begin
          picker = DhanScalper::OptionPicker.new(
            symbol_config,
            mode: :paper,
            csv_master: @csv_master
          )
          @cached_pickers[picker_key] = picker
        end
      end

      def save_session_data_to_file
        session_data_for_save = @session_data.dup
        session_data_for_save[:symbols_traded] = session_data_for_save[:symbols_traded].to_a
        session_data_for_save[:symbols_traded] = session_data_for_save[:symbols_traded].join(',')

        File.write(
          "data/session_#{@session_data[:session_id]}.json",
          JSON.pretty_generate(session_data_for_save)
        )
      rescue StandardError => e
        @logger.error "Failed to save session data: #{e.message}"
      end

      private

      attr_reader :session_reporter, :logger
    end
  end
end
