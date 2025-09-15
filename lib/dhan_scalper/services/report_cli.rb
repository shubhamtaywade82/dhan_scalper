# frozen_string_literal: true

require_relative 'session_reporter'

module DhanScalper
  module Services
    # Reporting service wrapper for CLI
    class ReportCLIService
      def initialize(logger: Logger.new($stdout))
        @logger = logger
        @reporter = DhanScalper::Services::SessionReporter.new
      end

      def generate(session_id: nil, latest: false)
        if session_id
          @reporter.generate_report_for_session(session_id)
        elsif latest
          @reporter.generate_latest_session_report
        else
          list_available
        end
      end

      private

      def list_available
        sessions = @reporter.list_available_sessions
        if sessions.empty?
          puts 'No session reports found in data/reports/ directory'
          return
        end

        puts 'Available Sessions:'
        puts '=' * 50
        sessions.each do |session|
          puts "#{session[:session_id]} - #{session[:created]} (#{session[:size]} bytes)"
        end
        puts
        puts 'Use: dhan_scalper report --session-id SESSION_ID'
        puts 'Or: dhan_scalper report --latest'
      end
    end
  end
end
