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
      context "with IN country and aadhaar flag enabled" do
        before do
          identity.update!(country: "IN")
          Flipper.enable(:authbridge_aadhaar_2025_07_10, identity)
        end
        after { Flipper.disable(:authbridge_aadhaar_2025_07_10) }

        it "returns :aadhaar" do
          expect(identity.required_verification_method).to eq(:aadhaar)
        end
      end

      context "with no flags enabled" do
        it "returns :document" do
          expect(identity.required_verification_method).to eq(:document)
        end
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
end
