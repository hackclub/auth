# frozen_string_literal: true

require "rails_helper"

RSpec.describe TombstonedEmail do
  describe ".digest" do
    it "produces a hex string" do
      expect(described_class.digest("test@example.com")).to match(/\A[a-f0-9]{64}\z/)
    end

    it "normalizes case" do
      expect(described_class.digest("Test@Example.COM")).to eq(described_class.digest("test@example.com"))
    end

    it "strips whitespace" do
      expect(described_class.digest("  test@example.com  ")).to eq(described_class.digest("test@example.com"))
    end

    it "produces different digests for different emails" do
      expect(described_class.digest("a@example.com")).not_to eq(described_class.digest("b@example.com"))
    end
  end

  describe ".tombstone!" do
    it "creates a record" do
      expect { described_class.tombstone!("gone@example.com") }.to change(described_class, :count).by(1)
    end

    it "is idempotent" do
      described_class.tombstone!("gone@example.com")
      expect { described_class.tombstone!("gone@example.com") }.not_to change(described_class, :count)
    end
  end

  describe ".tombstoned?" do
    it "returns false for unknown emails" do
      expect(described_class.tombstoned?("fresh@example.com")).to be false
    end

    it "returns true for tombstoned emails" do
      described_class.tombstone!("gone@example.com")
      expect(described_class.tombstoned?("gone@example.com")).to be true
    end

    it "matches case-insensitively" do
      described_class.tombstone!("gone@example.com")
      expect(described_class.tombstoned?("GONE@Example.COM")).to be true
    end
  end
end
