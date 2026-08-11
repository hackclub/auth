# frozen_string_literal: true

require "rails_helper"

RSpec.describe DeletionService do
  describe ".check_for_email" do
    it "returns nil when no tombstone exists" do
      expect(described_class.check_for_email("nobody@example.com")).to be_nil
    end

    it "returns the deletion record when email is tombstoned" do
      deletion = Deletion.create!(email_hash: Deletion.hash_email("gone@example.com"))
      expect(described_class.check_for_email("gone@example.com")).to eq(deletion)
    end

    it "matches case-insensitively" do
      Deletion.create!(email_hash: Deletion.hash_email("gone@example.com"))
      expect(described_class.check_for_email("GONE@Example.COM")).to be_present
    end
  end

  describe ".check_for_name_combos" do
    let(:dob) { Date.new(2005, 6, 15) }

    it "returns empty when no tombstone matches" do
      expect(described_class.check_for_name_combos("Nobody Here", dob)).to be_empty
    end

    it "finds a matching tombstone by name overlap" do
      hashes = Deletion.name_combo_hashes("John Michael Smith", dob)
      deletion = Deletion.create!(email_hash: "abc123", name_combos: hashes)

      results = described_class.check_for_name_combos("John Smith", dob)
      expect(results).to include(deletion)
    end

    it "does not match when DOB differs" do
      hashes = Deletion.name_combo_hashes("John Smith", dob)
      Deletion.create!(email_hash: "abc123", name_combos: hashes)

      results = described_class.check_for_name_combos("John Smith", Date.new(2000, 1, 1))
      expect(results).to be_empty
    end

    it "matches regardless of token order" do
      hashes = Deletion.name_combo_hashes("John Smith", dob)
      deletion = Deletion.create!(email_hash: "abc123", name_combos: hashes)

      results = described_class.check_for_name_combos("Smith John", dob)
      expect(results).to include(deletion)
    end

    it "collides on shared name pairs across different people" do
      hashes = Deletion.name_combo_hashes("Carlos Miguel Rivera", dob)
      deletion = Deletion.create!(email_hash: "abc123", name_combos: hashes)

      results = described_class.check_for_name_combos("Miguel Rivera", dob)
      expect(results).to include(deletion)
    end

    it "matches through diacritics" do
      hashes = Deletion.name_combo_hashes("José García", dob)
      deletion = Deletion.create!(email_hash: "abc123", name_combos: hashes)

      results = described_class.check_for_name_combos("Jose Garcia", dob)
      expect(results).to include(deletion)
    end
  end

  describe ".check_ip" do
    it "returns empty when no match" do
      expect(described_class.check_ip("192.168.1.1")).to be_empty
    end

    it "finds deletions containing the hashed IP" do
      deletion = Deletion.create!(
        email_hash: "abc123",
        session_ips: [ Deletion.hash_ip("10.0.0.1"), Deletion.hash_ip("10.0.0.2") ]
      )

      expect(described_class.check_ip("10.0.0.1")).to include(deletion)
    end
  end

  describe ".execute_deletion" do
    let(:identity) { create(:identity) }

    it "raises when identity is already tombstoned" do
      identity.update_columns(primary_email: "tombstoned+1@identity.invalid")
      expect {
        described_class.execute_deletion(identity, privacy_request_reference: "recASDASDASD")
      }.to raise_error(DeletionService::Error, /already tombstoned/)
    end

    it "raises when identity has a backend_user" do
      create(:backend_user, identity: identity)
      expect {
        described_class.execute_deletion(identity, privacy_request_reference: "recASDASDASD")
      }.to raise_error(DeletionService::Error, /backend_user/)
    end

    it "scrubs PII and creates tombstone record" do
      original_email = identity.primary_email

      described_class.execute_deletion(identity, privacy_request_reference: "recASDASDASD", logger: ->(_) { })

      identity.reload
      expect(identity.first_name).to eq("[REDACTED]")
      expect(identity.primary_email).to end_with("@identity.invalid")
      expect(identity.permabanned).to be true
      expect(Deletion.find_by(email_hash: Deletion.hash_email(original_email))).to be_present
    end

    it "logs a deletion_request activity" do
      expect {
        described_class.execute_deletion(identity, privacy_request_reference: "recASDASDASD", logger: ->(_) { })
      }.to change { PublicActivity::Activity.where(key: "identity.deletion_request").count }.by(1)
    end
  end
end
