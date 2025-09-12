#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "rspec"
require "colorize"

# Test categories and their descriptions
TEST_CATEGORIES = {
  unit: {
    description: "Unit Tests - Individual component testing",
    pattern: "spec/**/*_spec.rb",
    exclude: ["spec/integration/**/*", "spec/performance/**/*"],
  },
  integration: {
    description: "Integration Tests - Component interaction testing",
    pattern: "spec/integration/**/*_spec.rb",
  },
  performance: {
    description: "Performance Tests - Load and scalability testing",
    pattern: "spec/performance/**/*_spec.rb",
  },
  e2e: {
    description: "End-to-End Tests - Complete workflow testing",
    pattern: "spec/integration/end_to_end_trading_spec.rb",
  },
  all: {
    description: "All Tests - Complete test suite",
    pattern: "spec/**/*_spec.rb",
  },
}.freeze

class ComprehensiveTestRunner
  def initialize
    @results = {}
    @start_time = Time.now
  end

  def run_tests(categories = [:all])
    puts "🚀 Starting Comprehensive Test Suite for DhanScalper".colorize(:cyan)
    puts "=" * 80
    puts

    categories.each do |category|
      run_category(category)
    end

    print_summary
  end

  private

  def run_category(category)
    category_info = TEST_CATEGORIES[category]
    unless category_info
      puts "❌ Unknown test category: #{category}".colorize(:red)
      return
    end

    puts "📋 Running #{category_info[:description]}".colorize(:yellow)
    puts "-" * 60

    start_time = Time.now
    result = run_rspec_tests(category_info[:pattern])
    end_time = Time.now

    duration = end_time - start_time
    @results[category] = {
      success: result,
      duration: duration,
      pattern: category_info[:pattern],
    }

    status = result ? "✅ PASSED" : "❌ FAILED"
    color = result ? :green : :red
    puts "#{status} - #{category_info[:description]} (#{duration.round(2)}s)".colorize(color)
    puts
  end

  def run_rspec_tests(pattern)
    # Build RSpec command
    cmd = ["bundle", "exec", "rspec", pattern]

    # Add options
    cmd << "--format" << "documentation"
    cmd << "--color"

    # Run tests
    system(*cmd)
    $?.success?
  end

  def print_summary
    total_duration = Time.now - @start_time
    puts "=" * 80
    puts "📊 TEST SUMMARY".colorize(:cyan)
    puts "=" * 80

    total_tests = @results.size
    passed_tests = @results.count { |_, result| result[:success] }
    failed_tests = total_tests - passed_tests

    @results.each do |category, result|
      status = result[:success] ? "✅ PASSED" : "❌ FAILED"
      color = result[:success] ? :green : :red
      puts "#{status} #{category.to_s.upcase.ljust(15)} #{result[:duration].round(2)}s".colorize(color)
    end

    puts "-" * 80
    puts "Total Duration: #{total_duration.round(2)}s".colorize(:cyan)
    puts "Tests Passed: #{passed_tests}/#{total_tests}".colorize(passed_tests == total_tests ? :green : :red)

    if failed_tests > 0
      puts "⚠️  #{failed_tests} test category(ies) failed".colorize(:red)
      exit 1
    else
      puts "🎉 All tests passed!".colorize(:green)
    end
  end
end

# Main execution
if __FILE__ == $0
  categories = ARGV.map(&:to_sym)
  categories = [:all] if categories.empty?

  runner = ComprehensiveTestRunner.new
  runner.run_tests(categories)
end
