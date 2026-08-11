require "rails_helper"

RSpec.describe Identity, type: :model do
  let(:identity) { create(:identity) }

  describe "#required_verification_method" do
    context "when persona flag is enabled" do
      before { Flipper.enable(:persona_verification_2026_04_09, identity) }
      after { Flipper.disable(:persona_verification_2026_04_09) }

      it "returns :persona" do
        expect(identity.required_verification_method).to eq(:persona)
      end

      it "returns :persona even when aadhaar flag is also enabled" do
        Flipper.enable(:authbridge_aadhaar_2025_07_10, identity)
        identity.update!(country: "IN")

        expect(identity.required_verification_method).to eq(:persona)
      ensure
        Flipper.disable(:authbridge_aadhaar_2025_07_10)
      end
    end

    context "when persona flag is disabled" do
      it "returns :document" do
        expect(identity.required_verification_method).to eq(:document)
      end
    end
  end

  describe "#needs_persona?" do
    before { Flipper.enable(:persona_verification_2026_04_09, identity) }
    after { Flipper.disable(:persona_verification_2026_04_09) }

    it "returns true when persona flag is on and no approved/pending verifications" do
      expect(identity.needs_persona?).to be true
    end

    it "returns false when there is a pending persona verification" do
      create(:persona_verification, :pending, identity: identity)
      expect(identity.needs_persona?).to be false
    end

    it "returns false when there is an approved verification" do
      create(:persona_verification, :approved, identity: identity)
      expect(identity.needs_persona?).to be false
    end

    it "returns false when identity is permabanned" do
      identity.update!(permabanned: true)
      expect(identity.needs_persona?).to be false
    end
  end

  describe "#onboarding_step" do
    context "with persona flag enabled" do
      before { Flipper.enable(:persona_verification_2026_04_09, identity) }
      after { Flipper.disable(:persona_verification_2026_04_09) }

      it "returns :persona when no verification exists" do
        expect(identity.onboarding_step).to eq(:persona)
      end

      it "returns :address when verification is pending or approved but no address" do
        create(:persona_verification, :pending, identity: identity)
        expect(identity.onboarding_step).to eq(:address)
      end

      it "returns :submitted when verification exists and address is set" do
        create(:persona_verification, :approved, identity: identity)
        address = create(:address, identity: identity)
        identity.update!(primary_address: address)
        expect(identity.onboarding_step).to eq(:submitted)
      end
    end
  end

  describe "#persona_account_id" do
    it "can store and retrieve persona account ID" do
      identity.update!(persona_account_id: "act_abc123")
      expect(identity.reload.persona_account_id).to eq("act_abc123")
    end

    it "enforces uniqueness" do
      identity.update!(persona_account_id: "act_unique")
      other = build(:identity, persona_account_id: "act_unique")
      expect(other).not_to be_valid
    end
  end

  describe "#persona_verification_locked?" do
    before { Flipper.enable(:persona_verification_2026_04_09, identity) }
    after { Flipper.disable(:persona_verification_2026_04_09) }

    # Use bare attributes instead of :rejected trait to avoid persona_record
    # inquiry_id mismatch validation — we only need the status for counting.
    let(:rejected_attrs) { { status: :rejected, rejection_reason: "info_mismatch" } }

    it "returns false with no rejected verifications" do
      expect(identity.persona_verification_locked?).to be false
    end

    it "returns false with fewer rejected than the limit" do
      create_list(:persona_verification, 2, identity: identity, **rejected_attrs)
      expect(identity.persona_verification_locked?).to be false
    end

    it "returns true when rejected count hits the limit" do
      create_list(:persona_verification, Identity::MAX_PERSONA_ATTEMPTS, identity: identity, **rejected_attrs)
      expect(identity.persona_verification_locked?).to be true
    end

    it "counts student ID verifications toward the limit" do
      create_list(:persona_verification, 2, identity: identity, **rejected_attrs)
      create(:persona_verification, identity: identity, type: "Verification::PersonaStudentIdVerification", **rejected_attrs)
      expect(identity.persona_verification_locked?).to be true
    end

    it "does not count ignored verifications" do
      create_list(:persona_verification, Identity::MAX_PERSONA_ATTEMPTS, identity: identity,
        **rejected_attrs, ignored_at: Time.current, ignored_reason: "persona attempts reset")
      expect(identity.persona_verification_locked?).to be false
    end

    it "does not count draft or pending verifications" do
      create_list(:persona_verification, 3, identity: identity, status: :draft)
      expect(identity.persona_verification_locked?).to be false
    end

    it "returns false when verification method is not persona" do
      Flipper.disable(:persona_verification_2026_04_09, identity)
      create_list(:persona_verification, Identity::MAX_PERSONA_ATTEMPTS, identity: identity, **rejected_attrs)
      expect(identity.persona_verification_locked?).to be false
    end
  end
end
