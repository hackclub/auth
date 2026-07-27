require "rails_helper"

RSpec.describe VerificationCase, type: :model do
  describe "state machine" do
    it "walks the happy path" do
      kase = create(:verification_case)
      expect(kase).to be_requested

      kase.send_link!
      expect(kase).to be_link_sent
      expect(kase.link_sent_at).to be_present

      kase.update!(document_class: "government_id")
      kase.submit_docs!
      kase.schedule_call!
      kase.hold_call!
      kase.approve!

      expect(kase).to be_approved
      expect(kase).to be_decided
    end

    it "cannot decide before the call is held" do
      kase = create(:verification_case, :docs_submitted)
      expect { kase.approve! }.to raise_error(AASM::InvalidTransition)
    end

    it "allows deciding from escalated" do
      kase = create(:verification_case, :escalated)
      expect { kase.deny! }.not_to raise_error
    end

    it "stamps retention and revokes the flag on decision" do
      kase = create(:verification_case, :call_held)
      doc = create(:verification_case_document, verification_case: kase)
      Flipper.enable(described_class::FLIPPER_FLAG, kase.identity)

      kase.approve!

      expect(doc.reload.retention_delete_at).to be_within(1.hour).of(described_class::RETENTION_PERIOD.from_now)
      expect(Flipper.enabled?(described_class::FLIPPER_FLAG, kase.identity)).to be(false)
    end
  end

  describe "alternative-docs validation" do
    it "requires a reason" do
      kase = build(:verification_case, document_class: "alternative", alternative_reason: nil)
      expect(kase).not_to be_valid
    end

    it "requires details when reason is other" do
      kase = build(:verification_case, document_class: "alternative", alternative_reason: "other", alternative_reason_details: nil)
      expect(kase).not_to be_valid
      kase.alternative_reason_details = "long story"
      expect(kase).to be_valid
    end
  end

  describe "single-use access token" do
    let(:kase) { create(:verification_case) }

    it "consumes exactly once" do
      token = kase.generate_access_token!
      expect(kase.consume_access_token!(token)).to be(true)
      expect(kase.reload.access_token_used_at).to be_present
      expect(kase.consume_access_token!(token)).to be(false)
    end

    it "rejects wrong and expired tokens" do
      token = kase.generate_access_token!
      expect(kase.consume_access_token!("nope")).to be(false)

      kase.update!(access_token_expires_at: 1.minute.ago)
      expect(kase.consume_access_token!(token)).to be(false)
    end
  end

  describe "auto-escalation rules" do
    it "flags young accounts" do
      kase = create(:verification_case)
      kase.identity.update_column(:created_at, 2.days.ago)
      expect(kase.auto_escalation_reasons).to include("account_age_under_minimum")
    end

    it "flags prior denied cases" do
      identity = create(:identity)
      create(:verification_case, identity: identity, status: :denied)
      kase = create(:verification_case, identity: identity)
      identity.update_column(:created_at, 1.year.ago)
      expect(kase.auto_escalation_reasons).to include("prior_denied_case")
    end

    it "flags geo mismatch from the signal snapshot" do
      kase = create(:verification_case)
      kase.identity.update_column(:created_at, 1.year.ago)
      kase.identity.update_column(:country, "US")
      kase.update!(persona_signal_snapshot: { "network_signals" => { "country_code" => "RO" } })
      expect(kase.auto_escalation_reasons).to include("geo_mismatch")
    end
  end

  describe "#capture_template_id" do
    it "uses the shared template for either document class, from ENV fallback" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("PERSONA_MANUAL_CAPTURE_TEMPLATE").and_return("itmpl_test123")

      expect(build(:verification_case, document_class: "government_id").capture_template_id).to eq("itmpl_test123")
      expect(build(:verification_case, document_class: "alternative", alternative_reason: "no_government_id").capture_template_id).to eq("itmpl_test123")
    end

    it "is nil before a document class is chosen" do
      expect(build(:verification_case).capture_template_id).to be_nil
    end
  end

  describe "#booking_url" do
    it "appends case metadata to the configured link" do
      kase = create(:verification_case, :docs_submitted)
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("CALCOM_MANUAL_VERIFICATION_BOOKING_URL").and_return("https://cal.example.com/team/verify")

      expect(kase.booking_url).to include("metadata%5BcasePublicId%5D=#{CGI.escape(kase.public_id)}")
    end
  end

  describe "events" do
    it "are append-only" do
      kase = create(:verification_case)
      event = kase.log_event!(:case_opened)
      expect { event.update!(key: "tampered") }.to raise_error(ActiveRecord::ReadOnlyRecord)
      expect { event.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end
  end
end
