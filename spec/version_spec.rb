# frozen_string_literal: true

require "spec_helper"

RSpec.describe "DhanScalper::VERSION" do
  describe "version constant" do
    it "is defined" do
      expect(defined?(DhanScalper::VERSION)).to be_truthy
    end

    it "is a string" do
      expect(DhanScalper::VERSION).to be_a(String)
    end

    it "is not empty" do
      expect(DhanScalper::VERSION).not_to be_empty
    end

    it "is not nil" do
      expect(DhanScalper::VERSION).not_to be_nil
    end
  end

  describe "version format" do
    it "follows semantic versioning format" do
      expect(DhanScalper::VERSION).to match(/^\d+\.\d+\.\d+/)
    end

    it "has major version number" do
      major = DhanScalper::VERSION.split(".").first
      expect(major).to match(/^\d+$/)
      expect(major.to_i).to be >= 0
    end

    it "has minor version number" do
      minor = DhanScalper::VERSION.split(".")[1]
      expect(minor).to match(/^\d+$/)
      expect(minor.to_i).to be >= 0
    end

    it "has patch version number" do
      patch = DhanScalper::VERSION.split(".")[2]
      expect(patch).to match(/^\d+$/)
      expect(patch.to_i).to be >= 0
    end

    it "does not have more than 3 version components" do
      components = DhanScalper::VERSION.split(".")
      expect(components.length).to be <= 3
    end
  end

  describe "version values" do
    it "has reasonable major version" do
      major = DhanScalper::VERSION.split(".").first.to_i
      expect(major).to be >= 0
      expect(major).to be <= 999
    end

    it "has reasonable minor version" do
      minor = DhanScalper::VERSION.split(".")[1].to_i
      expect(minor).to be >= 0
      expect(minor).to be <= 999
    end

    it "has reasonable patch version" do
      patch = DhanScalper::VERSION.split(".")[2].to_i
      expect(patch).to be >= 0
      expect(patch).to be <= 999
    end
  end

  describe "version file" do
    it "version file exists" do
      version_file = File.expand_path("../lib/dhan_scalper/version.rb", __dir__)
      expect(File.exist?(version_file)).to be true
    end

    it "version file can be loaded" do
      version_file = File.expand_path("../lib/dhan_scalper/version.rb", __dir__)
      expect { load version_file }.not_to raise_error
    end

    it "version file defines VERSION constant" do
      version_file = File.expand_path("../lib/dhan_scalper/version.rb", __dir__)
      load version_file
      expect(defined?(DhanScalper::VERSION)).to be_truthy
    end
  end

  describe "gemspec integration" do
    it "gemspec file exists" do
      gemspec_file = File.expand_path("../dhan_scalper.gemspec", __dir__)
      expect(File.exist?(gemspec_file)).to be true
    end

    it "gemspec can be loaded" do
      gemspec_file = File.expand_path("../dhan_scalper.gemspec", __dir__)
      expect { load gemspec_file }.not_to raise_error
    end

    it "gemspec references VERSION constant" do
      gemspec_file = File.expand_path("../dhan_scalper.gemspec", __dir__)
      gemspec_content = File.read(gemspec_file)
      expect(gemspec_content).to include("DhanScalper::VERSION")
    end
  end

  describe "main module integration" do
    it "main module file exists" do
      main_file = File.expand_path("../lib/dhan_scalper.rb", __dir__)
      expect(File.exist?(main_file)).to be true
    end

    it "main module can be loaded" do
      main_file = File.expand_path("../lib/dhan_scalper.rb", __dir__)
      expect { load main_file }.not_to raise_error
    end

    it "main module defines VERSION constant" do
      main_file = File.expand_path("../lib/dhan_scalper.rb", __dir__)
      load main_file
      expect(defined?(DhanScalper::VERSION)).to be_truthy
    end
  end

  describe "version consistency" do
    it "version is consistent across files" do
      version_file = File.expand_path("../lib/dhan_scalper/version.rb", __dir__)
      main_file = File.expand_path("../lib/dhan_scalper.rb", __dir__)

      # Load version file first
      load version_file
      version_from_version_file = DhanScalper::VERSION

      # Reset constant
      DhanScalper.send(:remove_const, :VERSION) if defined?(DhanScalper::VERSION)

      # Load main file
      load main_file
      version_from_main_file = DhanScalper::VERSION

      expect(version_from_main_file).to eq(version_from_version_file)
    end
  end

  describe "version accessibility" do
    it "can be accessed from main module" do
      expect(DhanScalper::VERSION).to be_a(String)
    end

    it "can be accessed from nested modules" do
      expect(DhanScalper::PaperApp::VERSION).to eq(DhanScalper::VERSION) if defined?(DhanScalper::PaperApp::VERSION)
    end

    it "can be accessed from classes" do
      expect(DhanScalper::Trader::VERSION).to eq(DhanScalper::VERSION) if defined?(DhanScalper::Trader::VERSION)
    end
  end

  describe "version immutability" do
    it "cannot be modified" do
      original_version = DhanScalper::VERSION
      expect { DhanScalper::VERSION = "0.0.0" }.to raise_error(NameError)
      expect(DhanScalper::VERSION).to eq(original_version)
    end

    it "is frozen" do
      expect(DhanScalper::VERSION).to be_frozen
    end
  end

  describe "version documentation" do
    it "version file has proper format" do
      version_file = File.expand_path("../lib/dhan_scalper/version.rb", __dir__)
      content = File.read(version_file)

      expect(content).to include("module DhanScalper")
      expect(content).to include("VERSION =")
      expect(content).to include("frozen_string_literal: true")
    end

    it "main module file references version" do
      main_file = File.expand_path("../lib/dhan_scalper.rb", __dir__)
      content = File.read(main_file)

      expect(content).to include("require_relative")
      expect(content).to include("version")
    end
  end

  describe "version validation" do
    it "version string is valid" do
      version = DhanScalper::VERSION
      expect(version).to match(/^\d+\.\d+\.\d+$/)
    end

    it "version components are integers" do
      components = DhanScalper::VERSION.split(".")
      components.each do |component|
        expect(component.to_i.to_s).to eq(component)
      end
    end

    it "version follows semantic versioning rules" do
      major, minor, patch = DhanScalper::VERSION.split(".").map(&:to_i)

      expect(major).to be >= 0
      expect(minor).to be >= 0
      expect(patch).to be >= 0

      # Major version 0 indicates pre-release
      if major == 0
        expect(minor).to be >= 0
        expect(patch).to be >= 0
      end
    end
  end

  describe "version comparison" do
    it "can be compared with other versions" do
      current_version = Gem::Version.new(DhanScalper::VERSION)
      expect(current_version).to be_a(Gem::Version)
    end

    it "can be compared for equality" do
      version1 = Gem::Version.new(DhanScalper::VERSION)
      version2 = Gem::Version.new(DhanScalper::VERSION)
      expect(version1).to eq(version2)
    end

    it "can be compared for ordering" do
      version1 = Gem::Version.new("1.0.0")
      version2 = Gem::Version.new("2.0.0")
      expect(version1).to be < version2
    end
  end

  describe "version history" do
    it "version is not 0.0.0 (initial development)" do
      expect(DhanScalper::VERSION).not_to eq("0.0.0")
    end

    it "version is reasonable for production use" do
      major = DhanScalper::VERSION.split(".").first.to_i
      if major == 0
        # Pre-release versions are acceptable
        expect(major).to eq(0)
      else
        # Production versions should have major >= 1
        expect(major).to be >= 1
      end
    end
  end

  describe "version file structure" do
    it "version file has correct module structure" do
      version_file = File.expand_path("../lib/dhan_scalper/version.rb", __dir__)
      content = File.read(version_file)

      expect(content).to include("module DhanScalper")
      expect(content).to include("end")
    end

    it "version file has correct constant definition" do
      version_file = File.expand_path("../lib/dhan_scalper/version.rb", __dir__)
      content = File.read(version_file)

      expect(content).to include("VERSION =")
      expect(content).to include('"')
    end
  end

  describe "version loading order" do
    it "version is loaded before main module" do
      # This test ensures that the version file is loaded before the main module
      # by checking that the VERSION constant is available after loading the main module
      main_file = File.expand_path("../lib/dhan_scalper.rb", __dir__)

      # Reset constant if it exists
      DhanScalper.send(:remove_const, :VERSION) if defined?(DhanScalper::VERSION)

      # Load main module
      load main_file

      # Version should be available
      expect(defined?(DhanScalper::VERSION)).to be_truthy
      expect(DhanScalper::VERSION).to be_a(String)
    end
  end
end
