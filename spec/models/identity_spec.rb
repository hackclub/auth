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

  describe "#requires_two_factor?" do
    it "is false by default" do
      expect(identity.requires_two_factor?).to be false
    end

    it "is true when the user enabled 2FA and has a method" do
      identity.update!(use_two_factor_authentication: true)
      identity.totps.create!.mark_verified!

      expect(identity.requires_two_factor?).to be true
    end

    it "is true when the admin override is set and a method exists, even without the user flag" do
      identity.update!(two_factor_required: true)
      identity.totps.create!.mark_verified!

      expect(identity.requires_two_factor?).to be true
    end

    it "is false when the admin override is set but no method exists" do
      identity.update!(two_factor_required: true)

      expect(identity.requires_two_factor?).to be false
    end
  end

  describe "#two_factor_enrollment_required?" do
    it "is true when the override is set and no method is enrolled" do
      identity.update!(two_factor_required: true)

      expect(identity.two_factor_enrollment_required?).to be true
    end

    it "is false once a method is enrolled" do
      identity.update!(two_factor_required: true)
      identity.totps.create!.mark_verified!

      expect(identity.two_factor_enrollment_required?).to be false
    end

    it "is false without the override" do
      expect(identity.two_factor_enrollment_required?).to be false
    end
  end
end
