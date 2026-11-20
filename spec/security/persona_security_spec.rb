require "rails_helper"

RSpec.describe "Persona security", type: :model do
  let(:identity) { create(:identity) }

  describe "encrypted fields at rest" do
    it "encrypts persona_session_token in the database" do
      verification = create(:persona_verification, :with_inquiry, identity: identity)
      raw = Verification.connection.select_value(
        "SELECT persona_session_token FROM verifications WHERE id = #{verification.id}"
      )

      expect(raw).to be_present
      expect(raw).not_to eq(verification.persona_session_token)
      expect(raw).to include("{") # AR encryption wraps in JSON
    end

    it "encrypts raw_json_response in the database" do
      record = create(:identity_persona_record, identity: identity,
        raw_json_response: '{"secret": "sensitive_data_here"}')
      raw = Identity::PersonaRecord.connection.select_value(
        "SELECT raw_json_response FROM identity_persona_records WHERE id = #{record.id}"
      )

      expect(raw).to be_present
      expect(raw).not_to include("sensitive_data_here")
    end

    it "decrypts persona_session_token when reading" do
      token = "session_tok_#{SecureRandom.hex(16)}"
      verification = create(:persona_verification, identity: identity,
        persona_session_token: token, persona_inquiry_id: "inq_enc_test")

      reloaded = Verification::PersonaVerification.find(verification.id)
      expect(reloaded.persona_session_token).to eq(token)
    end

    it "decrypts raw_json_response when reading" do
      json = '{"data": {"attributes": {"status": "approved"}}}'
      record = create(:identity_persona_record, identity: identity,
        raw_json_response: json)

      reloaded = Identity::PersonaRecord.find(record.id)
      expect(reloaded.raw_json_response).to eq(json)
    end
  end

  describe "soft deletion" do
    it "persona records are not permanently deleted" do
      record = create(:identity_persona_record, identity: identity)
      record_id = record.id

      record.destroy

      expect(Identity::PersonaRecord.find_by(id: record_id)).to be_nil
      expect(Identity::PersonaRecord.with_deleted.find(record_id)).to be_present
      expect(Identity::PersonaRecord.with_deleted.find(record_id).deleted_at).to be_present
    end
  end

  describe "persona_account_id uniqueness" do
    it "prevents two identities from having the same persona account" do
      identity.update!(persona_account_id: "act_unique_123")

      other = build(:identity, persona_account_id: "act_unique_123")
      expect(other).not_to be_valid
      expect(other.errors[:persona_account_id]).to be_present
    end

    it "allows nil persona_account_id on multiple identities" do
      identity.update!(persona_account_id: nil)
      other = create(:identity, persona_account_id: nil)

      expect(other).to be_valid
    end
  end

  describe "inquiry_id uniqueness on PersonaRecord" do
    it "prevents duplicate inquiry_ids" do
      create(:identity_persona_record, identity: identity, inquiry_id: "inq_unique")

      duplicate = build(:identity_persona_record, identity: identity, inquiry_id: "inq_unique")
      expect(duplicate).not_to be_valid
    end
  end

  describe "AASM transition guards" do
    it "cannot approve a draft verification (must go through pending)" do
      verification = create(:persona_verification, identity: identity)
      expect(verification).to be_draft

      expect { verification.approve! }.to raise_error(AASM::InvalidTransition)
    end

    it "cannot re-reject an already rejected verification" do
      verification = create(:persona_verification, :rejected, identity: identity)

      expect { verification.mark_as_rejected!("fraud") }.to raise_error(AASM::InvalidTransition)
    end

    it "cannot go from approved back to pending" do
      verification = create(:persona_verification, :approved, identity: identity)

      expect { verification.mark_pending! }.to raise_error(AASM::InvalidTransition)
    end
  end
end
