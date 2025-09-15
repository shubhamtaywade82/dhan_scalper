# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new(:spec)

require 'rubocop/rake_task'

RuboCop::RakeTask.new

desc 'Run RubyCritic code quality analysis'
task :rubycritic do
  sh 'bundle exec rubycritic lib/ --format html'
  puts 'RubyCritic report generated in tmp/rubycritic/'
end

task default: %i[spec rubocop]
