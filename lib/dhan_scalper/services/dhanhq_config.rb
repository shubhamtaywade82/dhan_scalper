# frozen_string_literal: true

require "dotenv/load"
require "DhanHQ"

module DhanScalper
  module Services
    # Configuration service for DhanHQ API
    class DhanHQConfig
      class << self
        # Configure DhanHQ with environment variables
        def configure
          DhanHQ.configure do |config|
            config.client_id = ENV.fetch("CLIENT_ID", nil)
            config.access_token = ENV.fetch("ACCESS_TOKEN", nil)
            config.base_url = ENV["BASE_URL"] || "https://api.dhan.co/v2"
          end

          # Set logging level
          log_level = ENV["LOG_LEVEL"]&.upcase || "INFO"
          DhanHQ.logger.level = case log_level
                                when "DEBUG" then Logger::DEBUG
                                when "INFO" then Logger::INFO
                                when "WARN" then Logger::WARN
                                when "ERROR" then Logger::ERROR
                                else Logger::INFO
                                end
        end

        # Check if configuration is valid
        # @return [Boolean] True if configuration is complete
        def configured?
          ENV.fetch("CLIENT_ID", nil) && ENV.fetch("ACCESS_TOKEN", nil)
        end

        # Get configuration status
        # @return [Hash] Configuration status
        def status
          {
            client_id_present: !ENV["CLIENT_ID"].nil?,
            access_token_present: !ENV["ACCESS_TOKEN"].nil?,
            base_url: ENV["BASE_URL"] || "https://api.dhan.co/v2",
            log_level: ENV["LOG_LEVEL"] || "INFO",
            configured: configured?
          }
        end

        # Validate configuration and raise error if invalid
        # @raise [StandardError] If configuration is invalid
        def validate!
          return if configured?

          missing = []
          missing << "CLIENT_ID" unless ENV["CLIENT_ID"]
          missing << "ACCESS_TOKEN" unless ENV["ACCESS_TOKEN"]

          raise StandardError, "Missing required environment variables: #{missing.join(", ")}"
        end

        # Get sample .env content
        # @return [String] Sample .env file content
        def sample_env
          <<~ENV
            # DhanHQ API Configuration
            CLIENT_ID=your_client_id_here
            ACCESS_TOKEN=your_access_token_here

            # Optional configuration
            BASE_URL=https://api.dhan.co/v2
            LOG_LEVEL=INFO
          ENV
        end
      end
    end
  end
end
