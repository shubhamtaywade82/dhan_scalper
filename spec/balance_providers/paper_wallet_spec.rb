# frozen_string_literal: true

require "spec_helper"

RSpec.describe DhanScalper::BalanceProviders::PaperWallet do
  let(:starting_balance) { 200_000.0 }
  let(:paper_wallet) { described_class.new(starting_balance: starting_balance) }

  describe "#initialize" do
    it "sets the starting balance correctly" do
      expect(paper_wallet.total_balance).to eq(starting_balance)
      expect(paper_wallet.available_balance).to eq(starting_balance)
      expect(paper_wallet.used_balance).to eq(0.0)
    end

    it "uses default starting balance when not specified" do
      default_wallet = described_class.new
      expect(default_wallet.total_balance).to eq(200_000.0)
    end

    it "handles different starting balance values" do
      custom_wallet = described_class.new(starting_balance: 500_000.0)
      expect(custom_wallet.total_balance).to eq(500_000.0)
      expect(custom_wallet.available_balance).to eq(500_000.0)
    end

    it "handles zero starting balance" do
      zero_wallet = described_class.new(starting_balance: 0.0)
      expect(zero_wallet.total_balance).to eq(0.0)
      expect(zero_wallet.available_balance).to eq(0.0)
    end

    it "handles negative starting balance" do
      negative_wallet = described_class.new(starting_balance: -1000.0)
      expect(negative_wallet.total_balance).to eq(-1000.0)
      expect(negative_wallet.available_balance).to eq(-1000.0)
    end
  end

  describe "#available_balance" do
    it "returns the current available balance" do
      expect(paper_wallet.available_balance).to eq(starting_balance)
    end

    it "reflects changes after balance updates" do
      paper_wallet.update_balance(50_000, type: :debit)
      expect(paper_wallet.available_balance).to eq(starting_balance - 50_000)
    end

    it "never goes below zero" do
      paper_wallet.update_balance(starting_balance + 1000, type: :debit)
      expect(paper_wallet.available_balance).to eq(0.0)
    end
  end

  describe "#total_balance" do
    it "returns the initial starting balance" do
      expect(paper_wallet.total_balance).to eq(starting_balance)
    end

    it "remains constant regardless of transactions" do
      paper_wallet.update_balance(50_000, type: :debit)
      paper_wallet.update_balance(25_000, type: :credit)
      expect(paper_wallet.total_balance).to eq(starting_balance)
    end
  end

  describe "#used_balance" do
    it "starts at zero" do
      expect(paper_wallet.used_balance).to eq(0.0)
    end

    it "increases with debit transactions" do
      paper_wallet.update_balance(50_000, type: :debit)
      expect(paper_wallet.used_balance).to eq(50_000.0)
    end

    it "decreases with credit transactions" do
      paper_wallet.update_balance(50_000, type: :debit)
      paper_wallet.update_balance(25_000, type: :credit)
      expect(paper_wallet.used_balance).to eq(25_000.0)
    end

    it "never goes below zero" do
      paper_wallet.update_balance(50_000, type: :debit)
      paper_wallet.update_balance(100_000, type: :credit)
      expect(paper_wallet.used_balance).to eq(0.0)
    end
  end

  describe "#update_balance" do
    context "with debit transactions" do
      it "reduces available balance" do
        initial_available = paper_wallet.available_balance
        paper_wallet.update_balance(50_000, type: :debit)
        expect(paper_wallet.available_balance).to eq(initial_available - 50_000)
      end

      it "increases used balance" do
        initial_used = paper_wallet.used_balance
        paper_wallet.update_balance(50_000, type: :debit)
        expect(paper_wallet.used_balance).to eq(initial_used + 50_000)
      end

      it "handles large debit amounts" do
        paper_wallet.update_balance(starting_balance, type: :debit)
        expect(paper_wallet.available_balance).to eq(0.0)
        expect(paper_wallet.used_balance).to eq(starting_balance)
      end

      it "handles debit amounts larger than available balance" do
        paper_wallet.update_balance(starting_balance + 1000, type: :debit)
        expect(paper_wallet.available_balance).to eq(0.0)
        expect(paper_wallet.used_balance).to eq(starting_balance)
      end
    end

    context "with credit transactions" do
      before do
        # First debit some amount to have used balance
        paper_wallet.update_balance(50_000, type: :debit)
      end

      it "increases available balance" do
        initial_available = paper_wallet.available_balance
        paper_wallet.update_balance(25_000, type: :credit)
        expect(paper_wallet.available_balance).to eq(initial_available + 25_000)
      end

      it "decreases used balance" do
        initial_used = paper_wallet.used_balance
        paper_wallet.update_balance(25_000, type: :credit)
        expect(paper_wallet.used_balance).to eq(initial_used - 25_000)
      end

      it "handles credit amounts larger than used balance" do
        paper_wallet.update_balance(100_000, type: :credit)
        expect(paper_wallet.available_balance).to eq(starting_balance)
        expect(paper_wallet.used_balance).to eq(0.0)
      end
    end

    context "with default type parameter" do
      it "defaults to debit when type is not specified" do
        initial_available = paper_wallet.available_balance
        paper_wallet.update_balance(50_000)
        expect(paper_wallet.available_balance).to eq(initial_available - 50_000)
      end
    end

    context "edge cases" do
      it "handles zero amount transactions" do
        initial_available = paper_wallet.available_balance
        initial_used = paper_wallet.used_balance

        paper_wallet.update_balance(0, type: :debit)
        expect(paper_wallet.available_balance).to eq(initial_available)
        expect(paper_wallet.used_balance).to eq(initial_used)
      end

      it "handles negative amount transactions" do
        initial_available = paper_wallet.available_balance
        initial_used = paper_wallet.used_balance

        paper_wallet.update_balance(-50_000, type: :debit)
        expect(paper_wallet.available_balance).to eq(initial_available)
        expect(paper_wallet.used_balance).to eq(initial_used)
      end

      it "handles very small amounts" do
        paper_wallet.update_balance(0.01, type: :debit)
        expect(paper_wallet.available_balance).to eq(starting_balance - 0.01)
        expect(paper_wallet.used_balance).to eq(0.01)
      end

      it "handles very large amounts" do
        large_amount = 1_000_000_000.0
        paper_wallet.update_balance(large_amount, type: :debit)
        expect(paper_wallet.available_balance).to eq(0.0)
        expect(paper_wallet.used_balance).to eq(starting_balance)
      end
    end
  end

  describe "#reset_balance" do
    it "resets to the specified amount" do
      paper_wallet.update_balance(50_000, type: :debit)
      paper_wallet.reset_balance(300_000.0)

      expect(paper_wallet.total_balance).to eq(300_000.0)
      expect(paper_wallet.available_balance).to eq(300_000.0)
      expect(paper_wallet.used_balance).to eq(0.0)
    end

    it "handles zero reset amount" do
      paper_wallet.reset_balance(0.0)
      expect(paper_wallet.total_balance).to eq(0.0)
      expect(paper_wallet.available_balance).to eq(0.0)
      expect(paper_wallet.used_balance).to eq(0.0)
    end

    it "handles negative reset amount" do
      paper_wallet.reset_balance(-1000.0)
      expect(paper_wallet.total_balance).to eq(-1000.0)
      expect(paper_wallet.available_balance).to eq(-1000.0)
      expect(paper_wallet.used_balance).to eq(0.0)
    end
  end

  describe "balance consistency" do
    it "maintains total_balance = available_balance + used_balance relationship" do
      paper_wallet.update_balance(50_000, type: :debit)
      paper_wallet.update_balance(25_000, type: :credit)

      expect(paper_wallet.total_balance).to eq(paper_wallet.available_balance + paper_wallet.used_balance)
    end

    it "maintains consistency across multiple transactions" do
      transactions = [
        { amount: 25_000, type: :debit },
        { amount: 10_000, type: :credit },
        { amount: 15_000, type: :debit },
        { amount: 5_000, type: :credit }
      ]

      transactions.each do |tx|
        paper_wallet.update_balance(tx[:amount], type: tx[:type])
        expect(paper_wallet.total_balance).to eq(paper_wallet.available_balance + paper_wallet.used_balance)
      end
    end
  end
end
