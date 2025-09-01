require "spec_helper"

RSpec.describe DhanScalper::OptionPicker do
  let(:cfg) do
    {
      "idx_sid" => "13",
      "strike_step" => 50,
      "expiry_wday" => 4
    }
  end
  let(:csv_master) { instance_double(DhanScalper::CsvMaster) }
  let(:picker) do
    p = described_class.new(cfg, mode: mode)
    p.instance_variable_set(:@csv_master, csv_master)
    p
  end
  let(:mode) { :live }

  describe "#nearest_strike" do
    it "rounds spot to nearest step" do
      expect(picker.nearest_strike(19768, 50)).to eq(19750)
    end
  end

  describe "#nearest_weekly" do
    it "returns next target weekday" do
      allow(Time).to receive(:now).and_return(Time.new(2023, 9, 11, 10, 0, 0)) # Monday
      expect(picker.nearest_weekly(4)).to eq("2023-09-14")
    end
  end

  describe "#fetch_first_expiry" do
    it "uses csv master expiries when available" do
      allow(picker).to receive(:get_underlying_symbol).and_return("NIFTY")
      allow(csv_master).to receive(:get_expiry_dates).with("NIFTY").and_return(["2023-09-14", "2023-09-21"])
      expect(picker.fetch_first_expiry).to eq("2023-09-14")
    end

    it "falls back when csv master returns none" do
      allow(picker).to receive(:get_underlying_symbol).and_return("NIFTY")
      allow(csv_master).to receive(:get_expiry_dates).and_return([])
      allow(picker).to receive(:fallback_expiry).and_return("2023-09-14")
      expect(picker.fetch_first_expiry).to eq("2023-09-14")
    end
  end

  describe "#index_by" do
    it "indexes an option chain" do
      chain = [{ strike: 100, option_type: "CE", security_id: "1" }]
      expect(picker.index_by(chain)).to eq({ [100, :CE] => "1" })
    end
  end

  describe "#get_underlying_symbol" do
    it "maps idx_sid to underlying" do
      expect(picker.get_underlying_symbol).to eq("NIFTY")
      bank = described_class.new(cfg.merge("idx_sid" => "23"), mode: :live)
      bank.instance_variable_set(:@csv_master, csv_master)
      expect(bank.get_underlying_symbol).to eq("BANKNIFTY")
      finn = described_class.new(cfg.merge("idx_sid" => "25"), mode: :live)
      finn.instance_variable_set(:@csv_master, csv_master)
      expect(finn.get_underlying_symbol).to eq("FINNIFTY")
      other = described_class.new(cfg.merge("idx_sid" => "999"), mode: :live)
      other.instance_variable_set(:@csv_master, csv_master)
      expect(other.get_underlying_symbol).to eq("NIFTY")
    end
  end

  describe "#pick" do
    before do
      allow(picker).to receive(:fetch_first_expiry).and_return("2023-09-14")
      allow(picker).to receive(:get_underlying_symbol).and_return("NIFTY")
    end

    it "builds option chain with security ids" do
      allow(csv_master).to receive(:get_security_id) do |_, _, strike, type|
        "#{type}_#{strike}"
      end
      res = picker.pick(current_spot: 19768)
      expect(res[:ce_sid][19750]).to eq("CE_19750")
      expect(res[:pe_sid][19750]).to eq("PE_19750")
    end

    context "when csv master fails" do
      before do
        allow(csv_master).to receive(:get_security_id).and_raise("boom")
      end

      context "in paper mode" do
        let(:mode) { :paper }

        it "returns mock data" do
          res = picker.pick(current_spot: 19768)
          expect(res[:ce_sid][19750]).to eq("PAPER_CE_19750")
        end
      end

      context "in live mode" do
        it "raises error" do
          expect { picker.pick(current_spot: 19768) }.to raise_error(/Failed to fetch option chain/)
        end
      end
    end
  end
end
