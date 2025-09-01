# frozen_string_literal: true

require "spec_helper"
require "yaml"

RSpec.describe DhanScalper::Config do
  let(:temp_config_file) { "test_data/test_config.yml" }
  let(:temp_config_content) do
    <<~YAML
      symbols: ["NIFTY", "BANKNIFTY"]
      global:
        min_profit_target: 2000
        max_day_loss: 3000
        charge_per_order: 25
        allocation_pct: 0.40
        slippage_buffer_pct: 0.02
        max_lots_per_trade: 15
        decision_interval: 15
        log_level: "DEBUG"
        tp_pct: 0.40
        sl_pct: 0.20
        trail_pct: 0.15
      paper:
        starting_balance: 300000
      SYMBOLS:
        NIFTY:
          idx_sid: "13"
          seg_idx: "IDX_I"
          seg_opt: "NSE_FNO"
          strike_step: 50
          lot_size: 75
          qty_multiplier: 2
          expiry_wday: 4
        BANKNIFTY:
          idx_sid: "23"
          seg_idx: "IDX_I"
          seg_opt: "NSE_FNO"
          strike_step: 100
          lot_size: 25
          qty_multiplier: 1
          expiry_wday: 4
    YAML
  end

  before do
    FileUtils.mkdir_p("test_data")
  end

  after do
    FileUtils.rm_rf("test_data") if Dir.exist?("test_data")
  end

  describe ".load" do
    context "without config file" do
      it "returns default configuration" do
        config = DhanScalper::Config.load(path: nil)

        expect(config["symbols"]).to eq(["NIFTY"])
        expect(config.dig("global", "min_profit_target")).to eq(1000.0)
        expect(config.dig("global", "max_day_loss")).to eq(1500.0)
        expect(config.dig("global", "charge_per_order")).to eq(20.0)
        expect(config.dig("global", "allocation_pct")).to eq(0.30)
        expect(config.dig("global", "slippage_buffer_pct")).to eq(0.01)
        expect(config.dig("global", "max_lots_per_trade")).to eq(10)
        expect(config.dig("global", "decision_interval")).to eq(10)
        expect(config.dig("global", "log_level")).to eq("INFO")
        expect(config.dig("global", "tp_pct")).to eq(0.35)
        expect(config.dig("global", "sl_pct")).to eq(0.18)
        expect(config.dig("global", "trail_pct")).to eq(0.12)
        expect(config.dig("paper", "starting_balance")).to eq(200000.0)
      end

      it "uses environment variables for NIFTY_IDX_SID" do
        allow(ENV).to receive(:fetch).with("NIFTY_IDX_SID", "13").and_return("99")

        config = DhanScalper::Config.load(path: nil)

        expect(config.dig("SYMBOLS", "NIFTY", "idx_sid")).to eq("99")
      end
    end

    context "with config file" do
      before do
        File.write(temp_config_file, temp_config_content)
      end

      it "loads configuration from file" do
        config = DhanScalper::Config.load(path: temp_config_file)

        expect(config["symbols"]).to eq(["NIFTY", "BANKNIFTY"])
        expect(config.dig("global", "min_profit_target")).to eq(2000)
        expect(config.dig("global", "max_day_loss")).to eq(3000)
        expect(config.dig("global", "charge_per_order")).to eq(25)
        expect(config.dig("global", "allocation_pct")).to eq(0.40)
        expect(config.dig("global", "slippage_buffer_pct")).to eq(0.02)
        expect(config.dig("global", "max_lots_per_trade")).to eq(15)
        expect(config.dig("global", "decision_interval")).to eq(15)
        expect(config.dig("global", "log_level")).to eq("DEBUG")
        expect(config.dig("global", "tp_pct")).to eq(0.40)
        expect(config.dig("global", "sl_pct")).to eq(0.20)
        expect(config.dig("global", "trail_pct")).to eq(0.15)
        expect(config.dig("paper", "starting_balance")).to eq(300000)
      end

      it "merges with defaults for missing keys" do
        partial_config = <<~YAML
          symbols: ["NIFTY"]
          global:
            min_profit_target: 2000
        YAML

        File.write(temp_config_file, partial_config)
        config = DhanScalper::Config.load(path: temp_config_file)

        expect(config["symbols"]).to eq(["NIFTY"])
        expect(config.dig("global", "min_profit_target")).to eq(2000)
        expect(config.dig("global", "max_day_loss")).to eq(1500.0) # default
        expect(config.dig("global", "charge_per_order")).to eq(20.0) # default
        expect(config.dig("paper", "starting_balance")).to eq(200000.0) # default
      end

      it "loads SYMBOLS configuration" do
        config = DhanScalper::Config.load(path: temp_config_file)

        expect(config.dig("SYMBOLS", "NIFTY", "idx_sid")).to eq("13")
        expect(config.dig("SYMBOLS", "NIFTY", "seg_idx")).to eq("IDX_I")
        expect(config.dig("SYMBOLS", "NIFTY", "seg_opt")).to eq("NSE_FNO")
        expect(config.dig("SYMBOLS", "NIFTY", "strike_step")).to eq(50)
        expect(config.dig("SYMBOLS", "NIFTY", "lot_size")).to eq(75)
        expect(config.dig("SYMBOLS", "NIFTY", "qty_multiplier")).to eq(2)
        expect(config.dig("SYMBOLS", "NIFTY", "expiry_wday")).to eq(4)

        expect(config.dig("SYMBOLS", "BANKNIFTY", "idx_sid")).to eq("23")
        expect(config.dig("SYMBOLS", "BANKNIFTY", "strike_step")).to eq(100)
        expect(config.dig("SYMBOLS", "BANKNIFTY", "lot_size")).to eq(25)
        expect(config.dig("SYMBOLS", "BANKNIFTY", "qty_multiplier")).to eq(1)
      end

      it "handles empty config file" do
        File.write(temp_config_file, "")
        config = DhanScalper::Config.load(path: temp_config_file)

        # Should return defaults
        expect(config["symbols"]).to eq(["NIFTY"])
        expect(config.dig("global", "min_profit_target")).to eq(1000.0)
      end

      it "handles invalid YAML gracefully" do
        File.write(temp_config_file, "invalid: yaml: content: [")
        config = DhanScalper::Config.load(path: temp_config_file)

        # Should return defaults
        expect(config["symbols"]).to eq(["NIFTY"])
        expect(config.dig("global", "min_profit_target")).to eq(1000.0)
      end

      it "handles non-existent file" do
        config = DhanScalper::Config.load(path: "non_existent.yml")

        # Should return defaults
        expect(config["symbols"]).to eq(["NIFTY"])
        expect(config.dig("global", "min_profit_target")).to eq(1000.0)
      end
    end

    context "with environment variable" do
      it "uses SCALPER_CONFIG environment variable" do
        allow(ENV).to receive(:[]).with("SCALPER_CONFIG").and_return(temp_config_file)
        File.write(temp_config_file, temp_config_content)

        config = DhanScalper::Config.load

        expect(config["symbols"]).to eq(["NIFTY", "BANKNIFTY"])
        expect(config.dig("global", "min_profit_target")).to eq(2000)
      end
    end
  end

  describe "configuration validation" do
    it "ensures required keys exist" do
      config = DhanScalper::Config.load(path: nil)

      expect(config).to have_key("symbols")
      expect(config).to have_key("global")
      expect(config).to have_key("paper")
      expect(config).to have_key("SYMBOLS")
    end

    it "ensures global configuration has all required keys" do
      config = DhanScalper::Config.load(path: nil)
      global = config["global"]

      expect(global).to have_key("min_profit_target")
      expect(global).to have_key("max_day_loss")
      expect(global).to have_key("charge_per_order")
      expect(global).to have_key("allocation_pct")
      expect(global).to have_key("slippage_buffer_pct")
      expect(global).to have_key("max_lots_per_trade")
      expect(global).to have_key("decision_interval")
      expect(global).to have_key("log_level")
      expect(global).to have_key("tp_pct")
      expect(global).to have_key("sl_pct")
      expect(global).to have_key("trail_pct")
    end

    it "ensures paper configuration has required keys" do
      config = DhanScalper::Config.load(path: nil)
      paper = config["paper"]

      expect(paper).to have_key("starting_balance")
    end

    it "ensures SYMBOLS configuration has required keys" do
      config = DhanScalper::Config.load(path: nil)
      nifty = config.dig("SYMBOLS", "NIFTY")

      expect(nifty).to have_key("idx_sid")
      expect(nifty).to have_key("seg_idx")
      expect(nifty).to have_key("seg_opt")
      expect(nifty).to have_key("strike_step")
      expect(nifty).to have_key("lot_size")
      expect(nifty).to have_key("qty_multiplier")
      expect(nifty).to have_key("expiry_wday")
    end
  end

  describe "data types" do
    it "preserves correct data types" do
      config = DhanScalper::Config.load(path: nil)

      expect(config["symbols"]).to be_a(Array)
      expect(config.dig("global", "min_profit_target")).to be_a(Numeric)
      expect(config.dig("global", "max_day_loss")).to be_a(Numeric)
      expect(config.dig("global", "charge_per_order")).to be_a(Numeric)
      expect(config.dig("global", "allocation_pct")).to be_a(Numeric)
      expect(config.dig("global", "slippage_buffer_pct")).to be_a(Numeric)
      expect(config.dig("global", "max_lots_per_trade")).to be_a(Numeric)
      expect(config.dig("global", "decision_interval")).to be_a(Numeric)
      expect(config.dig("global", "log_level")).to be_a(String)
      expect(config.dig("global", "tp_pct")).to be_a(Numeric)
      expect(config.dig("global", "sl_pct")).to be_a(Numeric)
      expect(config.dig("global", "trail_pct")).to be_a(Numeric)
      expect(config.dig("paper", "starting_balance")).to be_a(Numeric)
    end
  end

  describe "edge cases" do
    it "handles nil values in config" do
      config_with_nils = <<~YAML
        symbols: ["NIFTY"]
        global:
          min_profit_target: null
          max_day_loss: 1500
      YAML

      File.write(temp_config_file, config_with_nils)
      config = DhanScalper::Config.load(path: temp_config_file)

      expect(config.dig("global", "min_profit_target")).to eq(1000.0) # default
      expect(config.dig("global", "max_day_loss")).to eq(1500)
    end

    it "handles empty arrays and hashes" do
      config_with_empty = <<~YAML
        symbols: []
        global: {}
        paper: {}
        SYMBOLS: {}
      YAML

      File.write(temp_config_file, config_with_empty)
      config = DhanScalper::Config.load(path: temp_config_file)

      expect(config["symbols"]).to eq([])
      expect(config["global"]).to eq({})
      expect(config["paper"]).to eq({})
      expect(config["SYMBOLS"]).to eq({})
    end

    it "handles very large numbers" do
      config_with_large_numbers = <<~YAML
        symbols: ["NIFTY"]
        global:
          min_profit_target: 999999999
          max_day_loss: 999999999
          charge_per_order: 999999999
        paper:
          starting_balance: 999999999
      YAML

      File.write(temp_config_file, config_with_large_numbers)
      config = DhanScalper::Config.load(path: temp_config_file)

      expect(config.dig("global", "min_profit_target")).to eq(999999999)
      expect(config.dig("global", "max_day_loss")).to eq(999999999)
      expect(config.dig("global", "charge_per_order")).to eq(999999999)
      expect(config.dig("paper", "starting_balance")).to eq(999999999)
    end

    it "handles negative numbers" do
      config_with_negative = <<~YAML
        symbols: ["NIFTY"]
        global:
          min_profit_target: -1000
          max_day_loss: -1500
          charge_per_order: -20
        paper:
          starting_balance: -200000
      YAML

      File.write(temp_config_file, config_with_negative)
      config = DhanScalper::Config.load(path: temp_config_file)

      expect(config.dig("global", "min_profit_target")).to eq(-1000)
      expect(config.dig("global", "max_day_loss")).to eq(-1500)
      expect(config.dig("global", "charge_per_order")).to eq(-20)
      expect(config.dig("paper", "starting_balance")).to eq(-200000)
    end
  end
end
