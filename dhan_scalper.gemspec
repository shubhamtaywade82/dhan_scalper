# frozen_string_literal: true

require_relative "lib/dhan_scalper/version"

Gem::Specification.new do |spec|
  spec.name = "dhan_scalper"
  spec.version = DhanScalper::VERSION
  spec.authors = ["Shubham Taywade"]
  spec.email   = ["shubhamtaywade82@gmail.com"]

  spec.summary = "Automated options scalping bot built on DhanHQ v2 API."
  spec.description = <<~DESC
    DhanScalper is a Ruby gem that provides a bootable CLI application for automated
    options scalping. It integrates with the DhanHQ v2 API via the dhanhq-client gem,
    supports live and paper trading modes, includes Candle and CandleSeries models
    for OHLCV data, indicator calculations, allocation-based position sizing,
    and a TTY interactive dashboard for monitoring open/closed positions.
  DESC
  spec.homepage = "https://github.com/shubhamtaywade82/dhan_scalper"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  # spec.metadata["allowed_push_host"] = "TODO: Set to your gem server 'https://example.com'"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/shubhamtaywade82/dhan_scalper"
  spec.metadata["changelog_uri"] = "https://github.com/shubhamtaywade82/dhan_scalper/blob/main/CHANGELOG.md"
  spec.metadata["documentation_uri"] = "https://rubydoc.info/gems/dhan_scalper"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore .rspec spec/ .github/ .rubocop.yml]) ||
        f.end_with?(".gem")
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Core runtime dependencies
  spec.add_dependency "concurrent-ruby"
  spec.add_dependency "csv"
  spec.add_dependency "dotenv"
  spec.add_dependency "pastel"
  spec.add_dependency "ruby-technical-analysis"    # johnnypaper
  spec.add_dependency "technical-analysis"         # intrinio
  spec.add_dependency "thor"
  spec.add_dependency "tty-box"
  spec.add_dependency "tty-reader"
  spec.add_dependency "tty-screen"
  spec.add_dependency "tty-table"

  # Development dependencies
  spec.add_development_dependency "rake", ">= 13.0"
  spec.add_development_dependency "rspec", ">= 3.12"
  spec.add_development_dependency "webmock", ">= 3.19"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
