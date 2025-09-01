require "spec_helper"
require "yaml"

RSpec.describe DhanScalper::Config do
  describe ".load" do
    it "returns default configuration when file missing" do
      cfg = described_class.load(path: "/nonexistent.yml")
      expect(cfg).to include("symbols" => ["NIFTY"])
    end

    it "merges provided yaml file over defaults" do
      require "tempfile"
      Tempfile.create("cfg") do |file|
        file.write({"global" => {"min_profit_target" => 2000.0},
                    "SYMBOLS" => {"NIFTY" => {"lot_size" => 100}}}.to_yaml)
        file.flush
        cfg = described_class.load(path: file.path)
        expect(cfg.dig("global", "min_profit_target")).to eq(2000.0)
        expect(cfg.dig("SYMBOLS", "NIFTY", "lot_size")).to eq(100)
        # other global defaults remain
        expect(cfg.dig("global", "charge_per_order")).to eq(20.0)
      end
    end
  end
end
