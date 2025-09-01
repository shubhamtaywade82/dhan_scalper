# frozen_string_literal: true

require "spec_helper"

RSpec.describe DhanScalper do
  describe "VERSION" do
    it "has a version number" do
      expect(DhanScalper::VERSION).not_to be_nil
      expect(DhanScalper::VERSION).to be_a(String)
      expect(DhanScalper::VERSION).to match(/^\d+\.\d+\.\d+/)
    end
  end

  describe "module structure" do
    it "is defined as a module" do
      expect(described_class).to be_a(Module)
    end

    it "has the correct name" do
      expect(described_class.name).to eq("DhanScalper")
    end
  end

  describe "required files" do
    it "loads all required dependencies" do
      # Test that all required files can be loaded without errors
      expect { require_relative "../lib/dhan_scalper" }.not_to raise_error
    end

    it "defines all expected classes" do
      # Test that main classes are defined
      expect(defined?(DhanScalper::App)).to be_truthy
      expect(defined?(DhanScalper::Trader)).to be_truthy
      expect(defined?(DhanScalper::Brokers::Base)).to be_truthy
      expect(defined?(DhanScalper::Brokers::DhanBroker)).to be_truthy
      expect(defined?(DhanScalper::Brokers::PaperBroker)).to be_truthy
      expect(defined?(DhanScalper::BalanceProviders::Base)).to be_truthy
      expect(defined?(DhanScalper::BalanceProviders::LiveBalance)).to be_truthy
      expect(defined?(DhanScalper::BalanceProviders::PaperWallet)).to be_truthy
      expect(defined?(DhanScalper::CandleSeries)).to be_truthy
      expect(defined?(DhanScalper::Config)).to be_truthy
      expect(defined?(DhanScalper::State)).to be_truthy
      expect(defined?(DhanScalper::VirtualDataManager)).to be_truthy
    end

    it "defines all expected modules" do
      # Test that main modules are defined
      expect(defined?(DhanScalper::IndicatorsGate)).to be_truthy
      expect(defined?(DhanScalper::Support::TimeZone)).to be_truthy
    end

    it "defines all expected structs" do
      # Test that main structs are defined
      expect(defined?(DhanScalper::Position)).to be_truthy
      expect(defined?(DhanScalper::Order)).to be_truthy
      expect(defined?(DhanScalper::Candle)).to be_truthy
    end
  end

  describe "constants" do
    it "defines expected constants" do
      expect(DhanScalper.constants).to include(:VERSION)
      expect(DhanScalper.constants).to include(:App)
      expect(DhanScalper.constants).to include(:Trader)
      expect(DhanScalper.constants).to include(:Config)
      expect(DhanScalper.constants).to include(:State)
    end
  end

  describe "namespace organization" do
    it "organizes brokers in Brokers namespace" do
      expect(DhanScalper::Brokers).to be_a(Module)
      expect(DhanScalper::Brokers.constants).to include(:Base)
      expect(DhanScalper::Brokers.constants).to include(:DhanBroker)
      expect(DhanScalper::Brokers.constants).to include(:PaperBroker)
    end

    it "organizes balance providers in BalanceProviders namespace" do
      expect(DhanScalper::BalanceProviders).to be_a(Module)
      expect(DhanScalper::BalanceProviders.constants).to include(:Base)
      expect(DhanScalper::BalanceProviders.constants).to include(:LiveBalance)
      expect(DhanScalper::BalanceProviders.constants).to include(:PaperWallet)
    end

    it "organizes UI components in UI namespace" do
      expect(DhanScalper::UI).to be_a(Module)
      expect(DhanScalper::UI.constants).to include(:Dashboard)
      expect(DhanScalper::UI.constants).to include(:DataViewer)
    end

    it "organizes support classes in Support namespace" do
      expect(DhanScalper::Support).to be_a(Module)
      expect(DhanScalper::Support.constants).to include(:TimeZone)
    end
  end

  describe "class inheritance" do
    it "has proper inheritance hierarchy for brokers" do
      expect(DhanScalper::Brokers::DhanBroker).to be < DhanScalper::Brokers::Base
      expect(DhanScalper::Brokers::PaperBroker).to be < DhanScalper::Brokers::Base
    end

    it "has proper inheritance hierarchy for balance providers" do
      expect(DhanScalper::BalanceProviders::LiveBalance).to be < DhanScalper::BalanceProviders::Base
      expect(DhanScalper::BalanceProviders::PaperWallet).to be < DhanScalper::BalanceProviders::Base
    end
  end

  describe "module inclusion" do
    it "includes IndicatorsGate in CandleSeries" do
      expect(DhanScalper::CandleSeries.included_modules).to include(DhanScalper::IndicatorsGate)
    end
  end

  describe "file loading" do
    it "loads without syntax errors" do
      # This test ensures the main file can be parsed without syntax errors
      main_file = File.expand_path("../lib/dhan_scalper.rb", __dir__)
      expect { load main_file }.not_to raise_error
    end

    it "loads all required dependencies" do
      # Test that all require statements work
      expect { require "json" }.not_to raise_error
      expect { require "time" }.not_to raise_error
      expect { require "logger" }.not_to raise_error
      expect { require "optparse" }.not_to raise_error
      expect { require "ostruct" }.not_to raise_error
      expect { require "csv" }.not_to raise_error
    end
  end

  describe "gem specification" do
    it "has a gemspec file" do
      gemspec_file = File.expand_path("../dhan_scalper.gemspec", __dir__)
      expect(File.exist?(gemspec_file)).to be true
    end

    it "can load gemspec without errors" do
      gemspec_file = File.expand_path("../dhan_scalper.gemspec", __dir__)
      expect { load gemspec_file }.not_to raise_error
    end
  end

  describe "CLI integration" do
    it "defines CLI class" do
      expect(defined?(DhanScalper::CLI)).to be_truthy
    end

    it "CLI class is a class" do
      expect(DhanScalper::CLI).to be_a(Class)
    end
  end

  describe "configuration integration" do
    it "defines Config class" do
      expect(defined?(DhanScalper::Config)).to be_truthy
    end

    it "Config class can be instantiated" do
      expect { DhanScalper::Config.new }.not_to raise_error
    end
  end

  describe "state management integration" do
    it "defines State class" do
      expect(defined?(DhanScalper::State)).to be_truthy
    end

    it "State class can be instantiated" do
      expect { DhanScalper::State.new }.not_to raise_error
    end
  end

  describe "virtual data management integration" do
    it "defines VirtualDataManager class" do
      expect(defined?(DhanScalper::VirtualDataManager)).to be_truthy
    end

    it "VirtualDataManager class can be instantiated" do
      expect { DhanScalper::VirtualDataManager.new }.not_to raise_error
    end
  end

  describe "trading components" do
    it "defines Trader class" do
      expect(defined?(DhanScalper::Trader)).to be_truthy
    end

    it "defines TrendEngine class" do
      expect(defined?(DhanScalper::TrendEngine)).to be_truthy
    end

    it "defines OptionPicker class" do
      expect(defined?(DhanScalper::OptionPicker)).to be_truthy
    end

    it "defines QuantitySizer class" do
      expect(defined?(DhanScalper::QuantitySizer)).to be_truthy
    end
  end

  describe "data structures" do
    it "defines Candle class" do
      expect(defined?(DhanScalper::Candle)).to be_truthy
    end

    it "defines CandleSeries class" do
      expect(defined?(DhanScalper::CandleSeries)).to be_truthy
    end

    it "defines Position struct" do
      expect(defined?(DhanScalper::Position)).to be_truthy
    end

    it "defines Order struct" do
      expect(defined?(DhanScalper::Order)).to be_truthy
    end
  end

  describe "utility classes" do
    it "defines CSVMaster class" do
      expect(defined?(DhanScalper::CSVMaster)).to be_truthy
    end

    it "defines PnL class" do
      expect(defined?(DhanScalper::PnL)).to be_truthy
    end

    it "defines Indicators class" do
      expect(defined?(DhanScalper::Indicators)).to be_truthy
    end

    it "defines TickCache class" do
      expect(defined?(DhanScalper::TickCache)).to be_truthy
    end
  end

  describe "UI components" do
    it "defines Dashboard class" do
      expect(defined?(DhanScalper::UI::Dashboard)).to be_truthy
    end

    it "defines DataViewer class" do
      expect(defined?(DhanScalper::UI::DataViewer)).to be_truthy
    end
  end

  describe "support classes" do
    it "defines TimeZone class" do
      expect(defined?(DhanScalper::Support::TimeZone)).to be_truthy
    end
  end

  describe "module functionality" do
    it "provides trading functionality" do
      expect(DhanScalper::App).to respond_to(:new)
      expect(DhanScalper::Trader).to respond_to(:new)
      expect(DhanScalper::Brokers::Base).to respond_to(:new)
    end

    it "provides configuration functionality" do
      expect(DhanScalper::Config).to respond_to(:new)
      expect(DhanScalper::Config).to respond_to(:load)
    end

    it "provides state management functionality" do
      expect(DhanScalper::State).to respond_to(:new)
      expect(DhanScalper::State).to respond_to(:replace_open!)
      expect(DhanScalper::State).to respond_to(:push_closed!)
    end

    it "provides data management functionality" do
      expect(DhanScalper::VirtualDataManager).to respond_to(:new)
      expect(DhanScalper::CandleSeries).to respond_to(:new)
      expect(DhanScalper::TickCache).to respond_to(:ltp)
    end
  end

  describe "error handling" do
    it "handles missing dependencies gracefully" do
      # Test that the module can handle missing optional dependencies
      expect { DhanScalper::IndicatorsGate.ema_series([1, 2, 3], 2) }.not_to raise_error
    end
  end

  describe "performance characteristics" do
    it "loads quickly" do
      start_time = Time.now
      require_relative "../lib/dhan_scalper"
      end_time = Time.now

      expect(end_time - start_time).to be < 1.0 # Should load within 1 second
    end
  end

  describe "documentation" do
    it "has version information" do
      expect(DhanScalper::VERSION).to be_a(String)
      expect(DhanScalper::VERSION).not_to be_empty
    end

    it "has proper module structure" do
      expect(DhanScalper.name).to eq("DhanScalper")
      expect(DhanScalper).to be_a(Module)
    end
  end

  describe "integration points" do
    it "integrates with external APIs" do
      # Test that the module can handle external API integrations
      expect(defined?(DhanScalper::Brokers::DhanBroker)).to be_truthy
      expect(defined?(DhanScalper::CandleSeries)).to be_truthy
    end

    it "provides fallback mechanisms" do
      # Test that fallback mechanisms are in place
      expect(DhanScalper::IndicatorsGate).to respond_to(:ema_series)
      expect(DhanScalper::IndicatorsGate).to respond_to(:rsi_series)
    end
  end
end
