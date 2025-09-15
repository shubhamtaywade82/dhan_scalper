# frozen_string_literal: true

require "csv"
require "json"
require "fileutils"
require "time"
require_relative "../support/money"
require_relative "trading_day_service"
require_relative "../stores/redis_store"

module DhanScalper
  module Services
    class SessionReporter
      def initialize(config: nil, logger: nil, redis_store: nil)
        @data_dir = "data"
        @reports_dir = File.join(@data_dir, "reports")
        @logger = logger || Logger.new($stdout)
        @trading_day_service = TradingDayService.new(config: config || {}, logger: @logger)
        @redis_store = redis_store || DhanScalper::Stores::RedisStore.new

        # Connect to Redis if not already connected
        @redis_store.connect unless @redis_store.redis

        # Ensure the reports directory exists (for fallback)
        begin
          FileUtils.mkdir_p(@reports_dir)
          puts "[REPORTS] Reports directory created: #{@reports_dir}" if ENV["DHAN_LOG_LEVEL"] == "DEBUG"
        rescue StandardError => e
          puts "[REPORTS] Warning: Failed to create reports directory: #{e.message}"
          # Fallback to current directory if data directory creation fails
          @reports_dir = "reports"
          FileUtils.mkdir_p(@reports_dir)
        end
      end

      # Generate a comprehensive session report
      def generate_session_report(session_data)
        session_id = session_data[:session_id] || generate_session_id(session_data[:mode] || "PAPER")

        report_data = {
          session_id: session_id,
          start_time: session_data[:start_time],
          end_time: session_data[:end_time],
          duration_minutes: session_data[:duration_minutes],
          mode: session_data[:mode] || "paper",
          symbols_traded: session_data[:symbols_traded] || [],
          total_trades: session_data[:total_trades] || 0,
          successful_trades: session_data[:successful_trades] || 0,
          failed_trades: session_data[:failed_trades] || 0,
          total_pnl: session_data[:total_pnl] || 0.0,
          starting_balance: session_data[:starting_balance] || 0.0,
          ending_balance: session_data[:ending_balance] || 0.0,
          used_balance: session_data[:used_balance] || 0.0,
          total_balance: session_data[:total_balance] || 0.0,
          max_drawdown: session_data[:max_drawdown] || 0.0,
          max_profit: session_data[:max_profit] || 0.0,
          win_rate: session_data[:win_rate] || 0.0,
          average_trade_pnl: session_data[:average_trade_pnl] || 0.0,
          positions: session_data[:positions] || [],
          trades: session_data[:trades] || [],
          risk_metrics: session_data[:risk_metrics] || {},
          performance_summary: session_data[:performance_summary] || {},
        }

        # Save to Redis
        save_session_to_redis(session_id, report_data)

        # Generate console summary
        generate_console_summary(report_data)

        {
          session_id: session_id,
          redis_stored: true,
          report_data: report_data,
        }
      end

      # Generate report for a specific session
      def generate_report_for_session(session_id)
        report_data = load_session_from_redis(session_id)
        return nil unless report_data

        generate_console_summary(report_data)
        report_data
      end

      # Generate report for the latest session
      def generate_latest_session_report
        json_files = Dir.glob(File.join(@reports_dir, "*.json"))

        if json_files.empty?
          puts "No session reports found"
          return nil
        end

        # Get the latest file
        latest_file = json_files.max_by { |f| File.mtime(f) }
        report_data = JSON.parse(File.read(latest_file), symbolize_names: true)

        generate_console_summary(report_data)
        report_data
      end

      # List available sessions
      def list_available_sessions
        json_files = Dir.glob(File.join(@reports_dir, "*.json"))

        json_files.map do |file|
          data = JSON.parse(File.read(file), symbolize_names: true)
          {
            session_id: data[:session_id],
            created: File.mtime(file).strftime("%Y-%m-%d %H:%M:%S"),
            size: File.size(file),
          }
        end.sort_by { |s| s[:created] }.reverse
      end

      # Load or create session data for the current trading day
      def load_or_create_session(mode: "PAPER", starting_balance: 200_000.0)
        @trading_day_service.load_or_create_session(
          mode: mode,
          starting_balance: starting_balance,
          reports_dir: @reports_dir,
        )
      end

      # Finalize session data with end time and duration
      def finalize_session(session_data)
        @trading_day_service.finalize_session(session_data)
      end

      private

      def ensure_reports_directory
        return if Dir.exist?(@reports_dir)

        begin
          FileUtils.mkdir_p(@reports_dir)
          puts "[REPORTS] Created reports directory: #{@reports_dir}" if ENV["DHAN_LOG_LEVEL"] == "DEBUG"
        rescue StandardError => e
          puts "[REPORTS] Warning: Failed to create reports directory #{@reports_dir}: #{e.message}"
          # Fallback to current directory
          @reports_dir = "reports"
          FileUtils.mkdir_p(@reports_dir)
          puts "[REPORTS] Using fallback directory: #{@reports_dir}"
        end
      end

      def generate_session_id(mode: "PAPER")
        @trading_day_service.current_session_id(mode: mode)
      end

      # CSV report generation removed - using Redis only

      def generate_console_summary(report_data)
        puts "\n#{"=" * 80}"
        puts "📊 SESSION REPORT - #{report_data[:session_id]}"
        puts "=" * 80

        # Session Info
        puts "\n🕐 SESSION INFO:"
        puts "  Mode: #{report_data[:mode].upcase}"
        puts "  Duration: #{report_data[:duration_minutes]&.round(1)} minutes"
        puts "  Start: #{report_data[:start_time]}"
        puts "  End: #{report_data[:end_time]}"
        puts "  Symbols: #{report_data[:symbols_traded].is_a?(Array) ? report_data[:symbols_traded].join(", ") : report_data[:symbols_traded].to_s}"

        # Trading Performance
        puts "\n📈 TRADING PERFORMANCE:"
        puts "  Total Trades: #{report_data[:total_trades]}"
        puts "  Successful: #{report_data[:successful_trades]}"
        puts "  Failed: #{report_data[:failed_trades]}"
        puts "  Win Rate: #{report_data[:win_rate]&.round(2)}%"

        # Financial Summary - Use current balance data if available
        puts "\n💰 FINANCIAL SUMMARY:"
        if report_data[:mode] == "paper"
          # Get current balance data for paper mode
          balance_provider = DhanScalper::BalanceProviders::PaperWallet.new
          starting_balance = report_data[:starting_balance] || 200_000.0
          available_balance = balance_provider.available_balance
          used_balance = balance_provider.used_balance
          total_balance = balance_provider.total_balance
          total_pnl = total_balance - starting_balance
        else
          # Use cached data for other modes
          starting_balance = report_data[:starting_balance] || 0
          available_balance = report_data[:available_balance] || report_data[:ending_balance] || 0
          used_balance = report_data[:used_balance] || 0
          total_balance = report_data[:total_balance] || 0
          total_pnl = report_data[:total_pnl] || 0
        end

        puts "  Starting Balance: #{DhanScalper::Support::Money.format(starting_balance)}"
        puts "  Available Balance: #{DhanScalper::Support::Money.format(available_balance)}"
        puts "  Used Balance: #{DhanScalper::Support::Money.format(used_balance)}"
        puts "  Total Balance: #{DhanScalper::Support::Money.format(total_balance)}"
        puts "  Total P&L: #{DhanScalper::Support::Money.format(total_pnl)}"
        puts "  Max Profit: #{DhanScalper::Support::Money.format(report_data[:max_profit] || 0)}"
        puts "  Max Drawdown: #{DhanScalper::Support::Money.format(report_data[:max_drawdown] || 0)}"
        puts "  Avg Trade P&L: #{DhanScalper::Support::Money.format(report_data[:average_trade_pnl] || 0)}"

        # Performance Rating
        pnl = total_pnl.to_f
        if pnl.positive?
          puts "\n✅ SESSION RESULT: PROFITABLE"
        elsif pnl.negative?
          puts "\n❌ SESSION RESULT: LOSS"
        else
          puts "\n➖ SESSION RESULT: BREAKEVEN"
        end

        # Risk Metrics
        if report_data[:risk_metrics]&.any?
          puts "\n⚠️  RISK METRICS:"
          report_data[:risk_metrics].each do |key, value|
            puts "  #{key.to_s.tr("_", " ").capitalize}: #{value}"
          end
        end

        puts "=" * 80
        puts "📁 Reports saved to: #{@reports_dir}"
        puts "=" * 80
      end

      private

      def save_session_to_redis(session_id, report_data)
        key = "dhan_scalper:v1:session:#{session_id}"

        # Convert report data to Redis-compatible format
        redis_data = prepare_report_data_for_redis(report_data)

        # Store as JSON in Redis
        @redis_store.redis.set(key, JSON.pretty_generate(redis_data))
        @redis_store.redis.expire(key, 86_400) # 24 hours TTL

        # Store session metadata
        store_session_metadata(session_id, report_data)

        @logger.info("[REPORTS] Saved session #{session_id} to Redis", component: "SessionReporter")
      rescue StandardError => e
        @logger.error("[REPORTS] Failed to save session #{session_id} to Redis: #{e.message}")
      end

      def load_session_from_redis(session_id)
        key = "dhan_scalper:v1:session:#{session_id}"
        data = @redis_store.redis.get(key)

        return nil unless data

        session_data = JSON.parse(data, symbolize_names: true)

        # Convert symbols_traded back to Set if it's an Array
        if session_data[:symbols_traded].is_a?(Array)
          session_data[:symbols_traded] = Set.new(session_data[:symbols_traded])
        end

        @logger.info("[REPORTS] Loaded session #{session_id} from Redis", component: "SessionReporter")

        session_data
      rescue StandardError => e
        @logger.error("[REPORTS] Failed to load session #{session_id} from Redis: #{e.message}", component: "SessionReporter")
        nil
      end

      def prepare_report_data_for_redis(report_data)
        # Convert Set to Array for JSON serialization
        prepared_data = report_data.dup

        if prepared_data[:symbols_traded].is_a?(Set)
          prepared_data[:symbols_traded] = prepared_data[:symbols_traded].to_a
        end

        # Ensure all values are JSON-serializable
        prepared_data.transform_values do |value|
          case value
          when Time
            value.iso8601
          when BigDecimal
            value.to_f
          when Set
            value.to_a
          else
            value
          end
        end
      end

      def store_session_metadata(session_id, report_data)
        metadata_key = "dhan_scalper:v1:session_meta:#{session_id}"

        # Handle start_time and end_time - they might be Time objects or strings
        start_time = report_data[:start_time]
        start_time = start_time.is_a?(Time) ? start_time.iso8601 : (start_time || Time.now.iso8601)

        end_time = report_data[:end_time]
        end_time = end_time.is_a?(Time) ? end_time.iso8601 : (end_time || Time.now.iso8601)

        metadata = {
          session_id: session_id,
          mode: report_data[:mode],
          start_time: start_time,
          end_time: end_time,
          total_pnl: report_data[:total_pnl] || 0.0,
          total_trades: report_data[:total_trades] || 0,
          status: report_data[:status] || "completed",
          created_at: Time.now.iso8601,
        }

        @redis_store.redis.hset(metadata_key, metadata.transform_keys(&:to_s))
        @redis_store.redis.expire(metadata_key, 86_400) # 24 hours TTL
      end
    end
  end
end
