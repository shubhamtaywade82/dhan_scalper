# frozen_string_literal: true

require "DhanHQ"

module DhanScalper
  module Services
    # Global WebSocket cleanup service
    class WebSocketCleanup
      class << self
        # Register cleanup handlers for all WebSocket connections
        def register_cleanup
          @cleanup_registered ||= begin
            at_exit do
              cleanup_all_websockets
            end

            # Also register signal handlers for graceful shutdown
            Signal.trap("INT") do
              cleanup_all_websockets
              exit(0)
            end

            Signal.trap("TERM") do
              cleanup_all_websockets
              exit(0)
            end

            true
          end
        end

        # Clean up all WebSocket connections
        def cleanup_all_websockets
          puts "\n[WEBSOCKET] Cleaning up all connections..." if ENV["DHAN_LOG_LEVEL"] == "DEBUG"

          # Try multiple methods to disconnect all WebSocket connections
          methods_to_try = [
            -> { DhanHQ::WS.disconnect_all_local! },
            -> { DhanHQ::WebSocket.disconnect_all_local! },
            -> { DhanHQ::WS.disconnect_all! },
            -> { DhanHQ::WebSocket.disconnect_all! }
          ]

          methods_to_try.each do |method|
            begin
              method.call
              puts "[WEBSOCKET] Successfully disconnected all connections" if ENV["DHAN_LOG_LEVEL"] == "DEBUG"
              return
            rescue StandardError => e
              puts "[WEBSOCKET] Warning: Failed to disconnect via method: #{e.message}" if ENV["DHAN_LOG_LEVEL"] == "DEBUG"
              next
            end
          end

          puts "[WEBSOCKET] Warning: Could not disconnect all WebSocket connections" if ENV["DHAN_LOG_LEVEL"] == "DEBUG"
        end

        # Check if cleanup is already registered
        def cleanup_registered?
          @cleanup_registered || false
        end
      end
    end
  end
end
