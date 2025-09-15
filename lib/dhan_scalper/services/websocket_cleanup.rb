# frozen_string_literal: true

require 'DhanHQ'

module DhanScalper
  module Services
    # Global WebSocket cleanup service
    class WebSocketCleanup
      class << self
        # Register cleanup handlers for all WebSocket connections
        def register_cleanup
          @register_cleanup ||= begin
            at_exit do
              cleanup_all_websockets
            end

            # Also register signal handlers for graceful shutdown
            Signal.trap('INT') do
              cleanup_all_websockets
              exit(0)
            end

            Signal.trap('TERM') do
              cleanup_all_websockets
              exit(0)
            end

            true
          end
        end

        # Clean up all WebSocket connections
        def cleanup_all_websockets
          puts "\n[WEBSOCKET] Cleaning up all connections..."

          # Try multiple methods to disconnect all WebSocket connections
          methods_to_try = [
            -> { DhanHQ::WS.disconnect_all_local! },
            -> { DhanHQ::WebSocket.disconnect_all_local! },
            -> { DhanHQ::WS.disconnect_all! },
            -> { DhanHQ::WebSocket.disconnect_all! }
          ]

          success = false
          methods_to_try.each do |method|
            method.call
            puts '[WEBSOCKET] Successfully disconnected all connections'
            success = true
            break
          rescue StandardError => e
            puts "[WEBSOCKET] Warning: Failed to disconnect via method: #{e.message}"
            next
          end

          return if success

          puts '[WEBSOCKET] Warning: Could not disconnect all WebSocket connections using standard methods'
          # Try to force cleanup any remaining connections
          begin
            # Force garbage collection to clean up any remaining WebSocket objects
            GC.start
            puts '[WEBSOCKET] Forced garbage collection to clean up remaining connections'
          rescue StandardError => e
            puts "[WEBSOCKET] Error during forced cleanup: #{e.message}"
          end
        end

        # Check if cleanup is already registered
        def cleanup_registered?
          @register_cleanup || false
        end
      end
    end
  end
end
