require "rails_helper"

RSpec.describe Identity::PersonaRecord, type: :model do
  let(:identity) { create(:identity) }

  subject { build(:identity_persona_record, identity: identity) }

  describe "associations" do
    it "belongs to identity" do
      expect(subject.identity).to eq(identity)
    end

    it "has one persona verification" do
      record = create(:identity_persona_record, identity: identity)
      verification = create(:persona_verification, :pending, identity: identity, persona_record: record)

      expect(record.verification).to eq(verification)
    end
  end

  describe "validations" do
    it "is valid with all required attributes" do
      expect(subject).to be_valid
    end

    it "requires inquiry_id" do
      subject.inquiry_id = nil
      expect(subject).not_to be_valid
      expect(subject.errors[:inquiry_id]).to be_present
    end

    it "requires raw_json_response" do
      subject.raw_json_response = nil
      expect(subject).not_to be_valid
    end

    it "requires name_first" do
      subject.name_first = nil
      expect(subject).not_to be_valid
    end

    it "requires name_last" do
      subject.name_last = nil
      expect(subject).not_to be_valid
    end

    it "requires birthdate" do
      subject.birthdate = nil
      expect(subject).not_to be_valid
    end

    it "enforces uniqueness of inquiry_id" do
      create(:identity_persona_record, identity: identity, inquiry_id: "inq_duplicate")
      other = build(:identity_persona_record, identity: identity, inquiry_id: "inq_duplicate")
      expect(other).not_to be_valid
    end
  end

  describe "encryption" do
    it "encrypts raw_json_response" do
      record = create(:identity_persona_record, identity: identity)
      # AR encryption: the raw DB value should differ from the plaintext
      raw_db = Identity::PersonaRecord.connection.select_value(
        "SELECT raw_json_response FROM identity_persona_records WHERE id = #{record.id}"
      )
      expect(raw_db).not_to eq(record.raw_json_response)
    end
  end

  describe "soft delete" do
    it "supports acts_as_paranoid" do
      record = create(:identity_persona_record, identity: identity)
      record.destroy
      expect(record.deleted_at).to be_present
      expect(Identity::PersonaRecord.find_by(id: record.id)).to be_nil
      expect(Identity::PersonaRecord.with_deleted.find(record.id)).to eq(record)
    end
  end

  describe "break glass records" do
    it "has many break_glass_records" do
      expect(subject).to respond_to(:break_glass_records)
    end
  end

  describe "#doc_json" do
    it "parses raw_json_response as JSON with symbol keys" do
      subject.raw_json_response = { data: { attributes: { name_first: "Heidi" } } }.to_json
      parsed = subject.doc_json
      expect(parsed).to be_a(Hash)
      expect(parsed[:data][:attributes][:name_first]).to eq("Heidi")
    end
  end
end
