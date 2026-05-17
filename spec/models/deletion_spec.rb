# frozen_string_literal: true

require "rails_helper"

RSpec.describe Deletion do
  describe ".hash_email" do
    it "produces a hex string" do
      expect(described_class.hash_email("test@example.com")).to match(/\A[a-f0-9]{64}\z/)
    end

    it "normalizes case" do
      expect(described_class.hash_email("Test@Example.COM")).to eq(described_class.hash_email("test@example.com"))
    end

    it "strips whitespace" do
      expect(described_class.hash_email("  test@example.com  ")).to eq(described_class.hash_email("test@example.com"))
    end

    it "produces different hashes for different emails" do
      expect(described_class.hash_email("a@example.com")).not_to eq(described_class.hash_email("b@example.com"))
    end
  end

  describe ".email_tombstoned?" do
    it "returns false for unknown emails" do
      expect(described_class.email_tombstoned?("fresh@example.com")).to be false
    end

    it "returns true for tombstoned emails" do
      described_class.create!(email_hash: described_class.hash_email("gone@example.com"))
      expect(described_class.email_tombstoned?("gone@example.com")).to be true
    end

    it "matches case-insensitively" do
      described_class.create!(email_hash: described_class.hash_email("gone@example.com"))
      expect(described_class.email_tombstoned?("GONE@Example.COM")).to be true
    end
  end

  describe ".tokenize_name" do
    it "lowercases and strips diacritics" do
      expect(described_class.tokenize_name("José García")).to eq(["jose", "garcia"])
    end

    it "splits on hyphens and apostrophes" do
      expect(described_class.tokenize_name("O'Brien-Smith")).to eq(["o", "brien", "smith"])
    end

    it "handles single-token names" do
      expect(described_class.tokenize_name("Suharto")).to eq(["suharto"])
    end

    it "collapses whitespace" do
      expect(described_class.tokenize_name("  John   Michael   Smith  ")).to eq(["john", "michael", "smith"])
    end
  end

  describe ".name_combo_hashes" do
    let(:dob) { Date.new(2008, 3, 15) }

    it "generates pairwise hashes for multi-token names" do
      hashes = described_class.name_combo_hashes("Mohammed J Random", dob)
      expect(hashes.size).to eq(3)
      expect(hashes).to all(match(/\A[a-f0-9]{64}\z/))
    end

    it "generates a single hash for single-token names" do
      hashes = described_class.name_combo_hashes("Suharto", dob)
      expect(hashes.size).to eq(1)
    end

    it "produces the same hashes regardless of token order" do
      hashes_a = described_class.name_combo_hashes("John Smith", dob)
      hashes_b = described_class.name_combo_hashes("Smith John", dob)
      expect(hashes_a).to match_array(hashes_b)
    end

    it "produces different hashes for different DOBs" do
      hashes_a = described_class.name_combo_hashes("John Smith", Date.new(2008, 3, 15))
      hashes_b = described_class.name_combo_hashes("John Smith", Date.new(2009, 1, 1))
      expect(hashes_a).not_to eq(hashes_b)
    end

    it "returns empty array for empty name" do
      expect(described_class.name_combo_hashes("", dob)).to eq([])
    end
  end

  describe ".name_combo_hashes_for_identity" do
    let(:dob) { Date.new(2008, 3, 15) }

    it "includes tokens from both preferred and legal names" do
      identity = build(:identity, first_name: "Mo", last_name: "Random", legal_first_name: "Mohammed", legal_last_name: "Random", birthday: dob)
      hashes = described_class.name_combo_hashes_for_identity(identity)
      # tokens: [mo, random, mohammed] (deduped) → 3 pairs
      expect(hashes.size).to eq(3)
    end

    it "deduplicates tokens across name fields" do
      identity = build(:identity, first_name: "John", last_name: "Smith", legal_first_name: "John", legal_last_name: "Smith", birthday: dob)
      hashes = described_class.name_combo_hashes_for_identity(identity)
      # tokens: [john, smith] → 1 pair
      expect(hashes.size).to eq(1)
    end

    it "works when legal name is absent" do
      identity = build(:identity, first_name: "John", last_name: "Smith", legal_first_name: nil, legal_last_name: nil, birthday: dob)
      hashes = described_class.name_combo_hashes_for_identity(identity)
      expect(hashes.size).to eq(1)
    end
  end

  describe ".hash_ip" do
    it "produces a hex string" do
      expect(described_class.hash_ip("192.168.1.1")).to match(/\A[a-f0-9]{64}\z/)
    end

    it "produces different hashes for different IPs" do
      expect(described_class.hash_ip("192.168.1.1")).not_to eq(described_class.hash_ip("10.0.0.1"))
    end
  end
end
