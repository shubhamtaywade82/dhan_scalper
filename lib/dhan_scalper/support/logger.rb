# frozen_string_literal: true

require "logger"

module DhanScalper
  module Support
    class Logger
      class << self
        attr_accessor :instance

        def setup(level: :info, output: $stdout)
          @instance = ::Logger.new(output)
          @instance.level = level_to_int(level)
          @instance.formatter = proc do |severity, datetime, progname, msg|
            "[#{datetime.strftime("%Y-%m-%d %H:%M:%S")}] #{severity.ljust(5)} -- #{progname}: #{msg}\n"
          end
          @instance
        end

        def info(message, component: "DhanScalper")
          instance&.info("#{component}: #{message}")
        end

        def debug(message, component: "DhanScalper")
          instance&.debug("#{component}: #{message}")
        end

        def warn(message, component: "DhanScalper")
          instance&.warn("#{component}: #{message}")
        end

        def error(message, component: "DhanScalper")
          instance&.error("#{component}: #{message}")
        end

        def fatal(message, component: "DhanScalper")
          instance&.fatal("#{component}: #{message}")
        end

        private

        def level_to_int(level)
          case level.to_s.downcase
          when "debug" then ::Logger::DEBUG
          when "info" then ::Logger::INFO
          when "warn" then ::Logger::WARN
          when "error" then ::Logger::ERROR
          when "fatal" then ::Logger::FATAL
          else ::Logger::INFO
          end
        end
      end
    end
  end
end
