# frozen_string_literal: true

require "spec_helper"

RSpec.describe DhanScalper::BalanceProviders::Base do
  let(:base_class) { Class.new(described_class) }
  let(:balance_provider) { base_class.new }

  describe "abstract methods" do
    it "raises NotImplementedError for available_balance" do
      expect { balance_provider.available_balance }.to raise_error(NotImplementedError)
    end

    it "raises NotImplementedError for total_balance" do
      expect { balance_provider.total_balance }.to raise_error(NotImplementedError)
    end

    it "raises NotImplementedError for used_balance" do
      expect { balance_provider.used_balance }.to raise_error(NotImplementedError)
    end

    it "raises NotImplementedError for update_balance" do
      expect { balance_provider.update_balance(100) }.to raise_error(NotImplementedError)
    end
  end

  describe "interface contract" do
    it "defines the required interface methods" do
      expect(described_class.instance_methods).to include(:available_balance)
      expect(described_class.instance_methods).to include(:total_balance)
      expect(described_class.instance_methods).to include(:used_balance)
      expect(described_class.instance_methods).to include(:update_balance)
    end

    it "ensures subclasses implement required methods" do
      # Create a subclass that doesn't implement required methods
      incomplete_class = Class.new(described_class)
      incomplete_provider = incomplete_class.new

      expect { incomplete_provider.available_balance }.to raise_error(NotImplementedError)
      expect { incomplete_provider.total_balance }.to raise_error(NotImplementedError)
      expect { incomplete_provider.used_balance }.to raise_error(NotImplementedError)
      expect { incomplete_provider.update_balance(100) }.to raise_error(NotImplementedError)
    end
  end

  describe "method signatures" do
    it "allows update_balance to accept type parameter" do
      # Test that the method signature allows the type parameter
      expect(described_class.instance_method(:update_balance).parameters).to include([:opt, :type])
    end
  end

  describe "inheritance" do
    it "can be inherited from" do
      expect { Class.new(described_class) }.not_to raise_error
    end

    it "maintains abstract method requirements" do
      child_class = Class.new(described_class) do
        def available_balance
          1000.0
        end
      end

      child_provider = child_class.new

      # Should still raise for unimplemented methods
      expect { child_provider.total_balance }.to raise_error(NotImplementedError)
      expect { child_provider.used_balance }.to raise_error(NotImplementedError)
      expect { child_provider.update_balance(100) }.to raise_error(NotImplementedError)
    end
  end

  describe "error messages" do
    it "provides clear error messages for NotImplementedError" do
      expect { balance_provider.available_balance }.to raise_error(NotImplementedError, /available_balance/)
      expect { balance_provider.total_balance }.to raise_error(NotImplementedError, /total_balance/)
      expect { balance_provider.used_balance }.to raise_error(NotImplementedError, /used_balance/)
      expect { balance_provider.update_balance(100) }.to raise_error(NotImplementedError, /update_balance/)
    end
  end
end
