require "rails_helper"
require_relative "../../support/shared_examples/verification_interface"
require_relative "../../support/shared_examples/rejectable"

RSpec.describe Verification::PersonaVerification, type: :model do
  let(:identity) { create(:identity) }

  subject { build(:persona_verification, identity: identity) }

  it_behaves_like "a verification type"
  it_behaves_like "a rejectable verification"

  describe "associations" do
    it "belongs to identity" do
      expect(subject.identity).to eq(identity)
    end

    it "belongs to persona_record (optional)" do
      expect(subject.persona_record).to be_nil
      expect(subject).to be_valid
    end

    it "belongs to identity_document (optional)" do
      expect(subject.identity_document).to be_nil
      expect(subject).to be_valid
    end
  end

  describe "encryption" do
    it "encrypts persona_session_token" do
      verification = create(:persona_verification, :with_inquiry, identity: identity)
      raw_db = Verification.connection.select_value(
        "SELECT persona_session_token FROM verifications WHERE id = #{verification.id}"
      )
      expect(raw_db).not_to eq(verification.persona_session_token)
    end
  end

  describe "AASM state machine" do
    describe "initial state" do
      it "starts as draft" do
        expect(subject).to be_draft
      end
    end

    describe "transitions" do
      it "transitions from draft to pending" do
        verification = create(:persona_verification, identity: identity)
        expect { verification.mark_pending! }.to change(verification, :status).from("draft").to("pending")
      end

      it "transitions from pending to approved" do
        verification = create(:persona_verification, :pending, identity: identity)
        expect { verification.approve! }.to change(verification, :status).from("pending").to("approved")
      end

      it "transitions from pending to rejected" do
        verification = create(:persona_verification, :pending, identity: identity)
        expect { verification.mark_as_rejected!("info_mismatch") }.to change(verification, :status).from("pending").to("rejected")
      end

      it "transitions from draft to rejected" do
        verification = create(:persona_verification, identity: identity)
        expect { verification.mark_as_rejected!("info_mismatch") }.to change(verification, :status).from("draft").to("rejected")
      end

      it "does not allow draft to approved" do
        verification = create(:persona_verification, identity: identity)
        expect { verification.approve! }.to raise_error(AASM::InvalidTransition)
      end

      it "does not allow approved to pending" do
        verification = create(:persona_verification, :approved, identity: identity)
        expect { verification.mark_pending! }.to raise_error(AASM::InvalidTransition)
      end

      it "does not allow rejected to approved" do
        verification = create(:persona_verification, :rejected, identity: identity)
        expect { verification.approve! }.to raise_error(AASM::InvalidTransition)
      end
    end

    describe "timestamps" do
      it "sets pending_at on mark_pending" do
        verification = create(:persona_verification, identity: identity)
        expect { verification.mark_pending! }.to change(verification, :pending_at).from(nil)
      end

      it "sets approved_at on approve" do
        verification = create(:persona_verification, :pending, identity: identity)
        expect { verification.approve! }.to change(verification, :approved_at).from(nil)
      end

      it "sets rejected_at on mark_as_rejected" do
        verification = create(:persona_verification, :pending, identity: identity)
        expect { verification.mark_as_rejected!("info_mismatch") }.to change(verification, :rejected_at).from(nil)
      end
    end
  end

  describe "rejection reasons" do
    let(:verification) { create(:persona_verification, :pending, identity: identity) }

    it "stores the rejection reason" do
      verification.mark_as_rejected!("info_mismatch")
      expect(verification.rejection_reason).to eq("info_mismatch")
    end

    it "stores rejection reason details" do
      verification.mark_as_rejected!("other", "something weird happened")
      expect(verification.rejection_reason_details).to eq("something weird happened")
    end

    it "marks fatal rejections with fatal flag" do
      verification.mark_as_rejected!("duplicate")
      expect(verification).to be_fatal
    end

    it "does not mark retryable rejections as fatal" do
      verification.mark_as_rejected!("poor_quality")
      expect(verification).not_to be_fatal
    end

    describe "mailer callbacks" do
      it "sends rejected_permanently for fatal rejections" do
        expect {
          verification.mark_as_rejected!("duplicate")
        }.to have_enqueued_mail(VerificationMailer, :rejected_permanently)
      end

      it "sends rejected_amicably for retryable rejections" do
        expect {
          verification.mark_as_rejected!("poor_quality")
        }.to have_enqueued_mail(VerificationMailer, :rejected_amicably)
      end
    end
  end

  describe "approval callbacks" do
    let(:persona_record) do
      create(:identity_persona_record,
        identity: identity,
        birthdate: Date.parse("2010-01-15"))
    end
    let(:verification) do
      create(:persona_verification, :pending,
        identity: identity,
        persona_record: persona_record)
    end

    it "sets ysws_eligible to true when 13 <= age <= 19" do
      # identity birthday is 2005-06-15, age ~20 in 2026
      # persona_record birthdate is 2010-01-15, age ~16 in 2026
      verification.approve!
      identity.reload
      expect(identity.ysws_eligible).to be true
    end

    it "sets ysws_eligible to false when age > 19" do
      persona_record.update!(birthdate: Date.parse("2000-01-01"))
      verification.approve!
      identity.reload
      expect(identity.ysws_eligible).to be false
    end

    it "sets ysws_eligible to false when age < 13" do
      persona_record.update!(birthdate: Date.parse("2020-01-01"))
      verification.approve!
      identity.reload
      expect(identity.ysws_eligible).to be false
    end

    it "sends the approved mailer" do
      expect {
        verification.approve!
      }.to have_enqueued_mail(VerificationMailer, :approved)
    end
  end

  describe "#generate_inquiry!" do
    let(:verification) { create(:persona_verification, identity: identity, persona_inquiry_id: nil) }
    let(:mock_inquiry) do
      Persona::Inquiry.new(
        id: "inq_abc123",
        status: "created",
        account_id: "act_xyz789",
        session_token: "session_tok_secret",
        verification_ids: [{ type: "verification/government-id", id: "ver_gov123" }]
      )
    end

    let(:mock_service) { instance_double(Persona::APIService) }

    before do
      allow(Persona).to receive(:instance).and_return(mock_service)
      allow(Rails.application.credentials).to receive(:persona).and_return(
        OpenStruct.new(template_id: "itmpl_test", api_key: "test_key", webhook_secret: "test_secret")
      )
    end

    it "calls the Persona service to create an inquiry" do
      allow(mock_service).to receive(:create_inquiry).and_return(mock_inquiry)

      verification.generate_inquiry!

      expect(mock_service).to have_received(:create_inquiry).with(
        template_id: anything,
        account_reference_id: identity.public_id,
        fields: hash_including(:"name-first", :"name-last", :"email-address")
      )
    end

    it "stores the inquiry_id and session_token" do
      allow(mock_service).to receive(:create_inquiry).and_return(mock_inquiry)

      verification.generate_inquiry!

      expect(verification.persona_inquiry_id).to eq("inq_abc123")
      expect(verification.persona_session_token).to eq("session_tok_secret")
    end

    it "stores the persona_account_id on the identity" do
      allow(mock_service).to receive(:create_inquiry).and_return(mock_inquiry)

      verification.generate_inquiry!

      identity.reload
      expect(identity.persona_account_id).to eq("act_xyz789")
    end

    it "raises if inquiry already exists" do
      verification.update!(persona_inquiry_id: "inq_existing")

      expect { verification.generate_inquiry! }.to raise_error(RuntimeError, /already has/)
    end
  end
end
