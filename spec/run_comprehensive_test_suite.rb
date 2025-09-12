#!/usr/bin/env ruby
# frozen_string_literal: true

require "colorize"
require "time"

class ComprehensiveTestSuite
  TEST_CATEGORIES = {
    unit: {
      name: "Unit Tests",
      pattern: "spec/unit/**/*_spec.rb",
      description: "Individual component testing with mocks and edge cases",
    },
    integration: {
      name: "Integration Tests",
      pattern: "spec/integration/**/*_spec.rb",
      description: "Component interaction testing with realistic data flow",
    },
    e2e: {
      name: "End-to-End Tests",
      pattern: "spec/end_to_end/**/*_spec.rb",
      description: "Complete workflow testing with full system simulation",
    },
    performance: {
      name: "Performance Tests",
      pattern: "spec/performance/**/*_spec.rb",
      description: "High-frequency trading and scalability testing",
    },
    all: {
      name: "All Tests",
      pattern: "spec/**/*_spec.rb",
      description: "Complete test suite execution",
    },
  }.freeze

  def initialize
    @results = {}
    @start_time = Time.now
    @total_tests = 0
    @passed_tests = 0
    @failed_tests = 0
  end

  def run_suite(categories = [:all])
    puts "🚀 Starting Comprehensive Test Suite for DhanScalper".colorize(:cyan)
    puts "=" * 80
    puts

    categories.each do |category|
      run_category(category)
    end

    print_final_summary
  end

  private

  def run_category(category)
    category_info = TEST_CATEGORIES[category]
    return unless category_info

    puts "📋 Running #{category_info[:name]}".colorize(:yellow)
    puts "   #{category_info[:description]}"
    puts

    start_time = Time.now
    result = run_rspec_tests(category_info[:pattern])
    duration = Time.now - start_time

    @results[category] = {
      duration: duration,
      result: result,
      pattern: category_info[:pattern],
    }

    print_category_summary(category, duration, result)
    puts
  end

  def run_rspec_tests(pattern)
    cmd = ["bundle", "exec", "rspec", pattern, "--format", "progress"]

    puts "   Command: #{cmd.join(" ")}".colorize(:light_blue)
    puts

    system(*cmd)
    $?.success?
  end

  def print_category_summary(_category, duration, success)
    status = success ? "✅ PASSED" : "❌ FAILED"
    color = success ? :green : :red

    puts "   #{status}".colorize(color)
    puts "   Duration: #{duration.round(2)}s"

    if success
      @passed_tests += 1
    else
      @failed_tests += 1
    end
    @total_tests += 1
  end

  def print_final_summary
    total_duration = Time.now - @start_time

    puts "=" * 80
    puts "📊 COMPREHENSIVE TEST SUITE SUMMARY".colorize(:cyan)
    puts "=" * 80
    puts

    # Overall results
    puts "🎯 Overall Results:"
    puts "   Total Categories: #{@total_tests}"
    puts "   Passed: #{@passed_tests}".colorize(:green)
    puts "   Failed: #{@failed_tests}".colorize(:red)
    puts "   Success Rate: #{(@passed_tests.to_f / @total_tests * 100).round(1)}%"
    puts "   Total Duration: #{total_duration.round(2)}s"
    puts

    # Category breakdown
    puts "📈 Category Breakdown:"
    @results.each do |category, data|
      status = data[:result] ? "✅" : "❌"
      color = data[:result] ? :green : :red
      puts "   #{status} #{category.to_s.upcase}: #{data[:duration].round(2)}s".colorize(color)
    end
    puts

    # Performance insights
    print_performance_insights
    puts

    # Recommendations
    print_recommendations
    puts

    # Exit with appropriate code
    exit(@failed_tests > 0 ? 1 : 0)
  end

  def print_performance_insights
    puts "⚡ Performance Insights:"

    fastest_category = @results.min_by { |_, data| data[:duration] }
    slowest_category = @results.max_by { |_, data| data[:duration] }

    puts "   Fastest: #{fastest_category[0].to_s.upcase} (#{fastest_category[1][:duration].round(2)}s)"
    puts "   Slowest: #{slowest_category[0].to_s.upcase} (#{slowest_category[1][:duration].round(2)}s)"

    avg_duration = @results.values.sum { |data| data[:duration] } / @results.length
    puts "   Average: #{avg_duration.round(2)}s"

    return unless slowest_category[1][:duration] > avg_duration * 2

    puts "   ⚠️  #{slowest_category[0].to_s.upcase} is significantly slower than average".colorize(:yellow)
  end

  def print_recommendations
    puts "💡 Recommendations:"

    if @failed_tests > 0
      puts "   • Fix failing tests before deployment"
      puts "   • Review test logs for specific failure details"
    end

    if @results[:performance] && @results[:performance][:duration] > 60
      puts "   • Consider optimizing performance tests"
      puts "   • Review high-frequency trading scenarios"
    end

    if @results[:e2e] && @results[:e2e][:duration] > 120
      puts "   • Consider breaking down end-to-end tests"
      puts "   • Review test data generation efficiency"
    end

    puts "   • Run tests regularly during development"
    puts "   • Monitor test performance over time"
    puts "   • Consider parallel test execution for large suites"
  end
end

# Main execution
if __FILE__ == $PROGRAM_NAME
  categories = if ARGV.include?("--all")
                 [:all]
               elsif ARGV.include?("--unit")
                 [:unit]
               elsif ARGV.include?("--integration")
                 [:integration]
               elsif ARGV.include?("--e2e")
                 [:e2e]
               elsif ARGV.include?("--performance")
                 [:performance]
               else
                 %i[unit integration e2e performance]
               end

  suite = ComprehensiveTestSuite.new
  suite.run_suite(categories)
end
