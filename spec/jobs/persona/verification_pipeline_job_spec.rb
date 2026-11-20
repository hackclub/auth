require "rails_helper"

RSpec.describe Persona::VerificationPipelineJob, type: :job do
  let(:identity) { create(:identity) }
  let(:record) { create(:identity_persona_record, identity: identity) }

  before { allow(ResemblanceNoticerEngine).to receive(:run) }

  def pending_verification(**attrs)
    create(:persona_verification, :pending, identity: identity, persona_record: record, persona_inquiry_id: record.inquiry_id, **attrs)
  end

  context "with a staff-created inquiry" do
    let(:verification) { pending_verification(issues: [ Verification::PersonaVerification::STAFF_CREATED_ISSUE ]) }

    it "sends it to manual review even when decisioning approves" do
      expect {
        described_class.perform_now(verification)
      }.to have_enqueued_job(Slack::NotifyReviewQueueJob)

      verification.reload
      expect(verification).to be_pending
      expect(verification.issues).to eq([ Verification::PersonaVerification::STAFF_CREATED_ISSUE ])
    end
  end

  context "with an ordinary inquiry" do
    let(:verification) { pending_verification }

    it "still auto-approves" do
      described_class.perform_now(verification)
      expect(verification.reload).to be_approved
    end
  end
end
