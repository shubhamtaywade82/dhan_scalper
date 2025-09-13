# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in dhan_scalper.gemspec
gemspec

gem "irb"
gem "rake", "~> 13.0"

gem "rspec", "~> 3.0"

gem "rubocop", "~> 1.21"
gem "rubocop-rake"

gem "rubocop-performance"

gem "rubocop-rspec"

gem "async", "~> 2.0"
gem "rubycritic", require: false, group: :development

gem "DhanHQ", git: "https://github.com/shubhamtaywade82/dhanhq-client.git", branch: "main"

gem "concurrent-ruby"
gem "dotenv"
gem "simplecov", require: false, group: :test
gem "terminal-table"
gem "thor" # CLI
gem "webmock", group: :test

# Redis optional runtime (used when TICK_CACHE_BACKEND=redis)
gem "connection_pool", ">= 2.4"
gem "redis", "~> 5.1"
