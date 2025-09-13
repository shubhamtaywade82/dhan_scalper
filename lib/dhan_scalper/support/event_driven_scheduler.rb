# frozen_string_literal: true

require "concurrent"
require "async"
require_relative "logger"

module DhanScalper
  module Support
    class EventDrivenScheduler
      def initialize
        @scheduled_tasks = Concurrent::Map.new
        @running = false
        @async_reactor = nil
        @mutex = Mutex.new
      end

      def start
        return if @running

        @mutex.synchronize do
          return if @running

          @running = true

          Logger.info("Starting event-driven scheduler", component: "EventScheduler")

          # Start async reactor in a separate thread
          @async_reactor = Thread.new do
            Async do |task|
              @reactor_task = task
              task.sleep(0.1) while @running
            end
          end
        end
      end

      def stop
        return unless @running

        # Use non-blocking approach for signal safety
        if @mutex.try_lock
          begin
            return unless @running

            @running = false

            Logger.info("Stopping event-driven scheduler", component: "EventScheduler")

            # Cancel all scheduled tasks
            @scheduled_tasks.each_value do |task|
              task.stop if task.respond_to?(:stop)
            end
            # Clear tasks outside of mutex to avoid trap context issues
            @scheduled_tasks = Concurrent::Map.new

            # Stop async reactor
            @async_reactor&.join(2)
            @async_reactor = nil
          ensure
            @mutex.unlock
          end
        else
          # If we can't get the lock, just set running to false
          # This is safe for signal handlers
          @running = false
        end
      end

      def running?
        @running
      end

      # Schedule a recurring task
      def schedule_recurring(name, interval_seconds)
        return unless @running

        # Cancel existing task with same name
        cancel_task(name)

        Logger.debug(
          "Scheduling recurring task '#{name}' with interval #{interval_seconds}s",
          component: "EventScheduler",
        )

        task = Async do |task|
          while @running
            begin
              yield
            rescue StandardError => e
              Logger.error(
                "Error in recurring task '#{name}': #{e.message}",
                component: "EventScheduler",
              )
            end

            task.sleep(interval_seconds) if @running
          end
        end

        @scheduled_tasks[name] = task
        task
      end

      # Schedule a one-time delayed task
      def schedule_once(name, delay_seconds)
        return unless @running

        # Cancel existing task with same name
        cancel_task(name)

        Logger.debug(
          "Scheduling one-time task '#{name}' with delay #{delay_seconds}s",
          component: "EventScheduler",
        )

        task = Async do |task|
          task.sleep(delay_seconds)
          return unless @running

          begin
            yield
          rescue StandardError => e
            Logger.error(
              "Error in one-time task '#{name}': #{e.message}",
              component: "EventScheduler",
            )
          ensure
            @scheduled_tasks.delete(name)
          end
        end

        @scheduled_tasks[name] = task
        task
      end

      # Schedule a task that runs immediately and then at intervals
      def schedule_immediate_recurring(name, interval_seconds)
        return unless @running

        # Cancel existing task with same name
        cancel_task(name)

        Logger.debug(
          "Scheduling immediate recurring task '#{name}' with interval #{interval_seconds}s",
          component: "EventScheduler",
        )

        task = Async do |task|
          # Run immediately first
          begin
            yield
          rescue StandardError => e
            Logger.error(
              "Error in immediate recurring task '#{name}': #{e.message}",
              component: "EventScheduler",
            )
          end

          # Then run at intervals
          while @running
            task.sleep(interval_seconds)
            break unless @running

            begin
              yield
            rescue StandardError => e
              Logger.error(
                "Error in immediate recurring task '#{name}': #{e.message}",
                component: "EventScheduler",
              )
            end
          end
        end

        @scheduled_tasks[name] = task
        task
      end

      # Cancel a specific task
      def cancel_task(name)
        task = @scheduled_tasks.delete(name)
        return unless task

        task.stop if task.respond_to?(:stop)
        Logger.debug("Cancelled task '#{name}'", component: "EventScheduler")
      end

      # Cancel all tasks
      def cancel_all_tasks
        @scheduled_tasks.each do |name, task|
          task.stop if task.respond_to?(:stop)
          Logger.debug("Cancelled task '#{name}'", component: "EventScheduler")
        end
        @scheduled_tasks.clear
      end

      # Get list of active tasks
      def active_tasks
        @scheduled_tasks.keys
      end

      # Wait for all tasks to complete (with timeout)
      def wait_for_completion(timeout_seconds: 5)
        return if @scheduled_tasks.empty?

        Logger.debug(
          "Waiting for #{@scheduled_tasks.size} tasks to complete",
          component: "EventScheduler",
        )

        start_time = Time.now
        while @running && !@scheduled_tasks.empty?
          break if Time.now - start_time > timeout_seconds

          sleep(0.1)
        end

        return unless @scheduled_tasks.any?

        Logger.warn(
          "Timeout waiting for tasks to complete: #{@scheduled_tasks.keys}",
          component: "EventScheduler",
        )
      end

      # Schedule a task with exponential backoff
      def schedule_with_backoff(name, initial_delay: 1, max_delay: 60, multiplier: 2)
        return unless @running

        cancel_task(name)

        Logger.debug(
          "Scheduling task '#{name}' with exponential backoff",
          component: "EventScheduler",
        )

        task = Async do |task|
          delay = initial_delay
          while @running
            begin
              yield
              # Reset delay on success
              delay = initial_delay
            rescue StandardError => e
              Logger.error(
                "Error in backoff task '#{name}': #{e.message}, retrying in #{delay}s",
                component: "EventScheduler",
              )

              task.sleep(delay)
              delay = [delay * multiplier, max_delay].min
            end
          end
        end

        @scheduled_tasks[name] = task
        task
      end

      # Schedule a task that runs on specific days/times
      def schedule_daily(name, hour: 9, minute: 0)
        return unless @running

        cancel_task(name)

        Logger.debug(
          "Scheduling daily task '#{name}' at #{hour}:#{minute.to_s.rjust(2, "0")}",
          component: "EventScheduler",
        )

        task = Async do |task|
          while @running
            now = Time.now
            next_run = Time.new(now.year, now.month, now.day, hour, minute, 0)

            # If time has passed today, schedule for tomorrow
            next_run += 24 * 60 * 60 if next_run <= now

            Logger.debug(
              "Next run for '#{name}': #{next_run}",
              component: "EventScheduler",
            )

            sleep_seconds = next_run - now
            task.sleep(sleep_seconds) if @running

            next unless @running

            begin
              yield
            rescue StandardError => e
              Logger.error(
                "Error in daily task '#{name}': #{e.message}",
                component: "EventScheduler",
              )
            end
          end
        end

        @scheduled_tasks[name] = task
        task
      end

      private

      def logger
        Logger
      end
    end
  end
end
