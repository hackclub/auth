require "rails_helper"

RSpec.describe Persona::LinkStaffInquiryJob, type: :job do
  let(:identity) { create(:identity) }
  let(:reviewer_identity) { create(:identity, primary_email: "reviewer@hackclub.com") }
  let!(:reviewer) { create(:backend_user, identity: reviewer_identity, manual_document_verifier: true) }
  let(:inquiry_id) { "inq_dashboard123" }
  let(:mock_service) { instance_double(Persona::APIService) }

  before { allow(Persona).to receive(:instance).and_return(mock_service) }

  def perform(creator: "reviewer@hackclub.com", reference_id: identity.public_id)
    described_class.perform_now(inquiry_id: inquiry_id, creator: creator, reference_id: reference_id)
  end

  it "creates a draft persona verification flagged for manual review" do
    expect { perform }.to change(Verification::PersonaVerification, :count).by(1)

    verification = identity.verifications.last
    expect(verification).to be_draft
    expect(verification.persona_inquiry_id).to eq(inquiry_id)
    expect(verification).to be_staff_created_inquiry
    expect(verification).not_to be_auto_approvable
  end

  it "records which reviewer linked it" do
    perform

    activity = PublicActivity::Activity.where("key LIKE ?", "%persona_inquiry_linked_by_staff").sole
    expect(activity.owner).to eq(reviewer)
    expect(activity.parameters[:inquiry_id]).to eq(inquiry_id)
  end

  it "matches the creator email case-insensitively" do
    expect { perform(creator: "Reviewer@HackClub.com") }.to change(Verification::PersonaVerification, :count).by(1)
  end

  it "ignores creators who aren't backend users" do
    expect { perform(creator: "someone@example.com") }.not_to change(Verification, :count)
  end

  it "ignores backend users without review rights" do
    reviewer.update!(manual_document_verifier: false)
    expect { perform }.not_to change(Verification, :count)
  end

  it "ignores deactivated backend users" do
    reviewer.deactivate!
    expect { perform }.not_to change(Verification, :count)
  end

  it "ignores a reference id that isn't an identity" do
    expect { perform(reference_id: "ident!nope") }.not_to change(Verification, :count)
  end

  it "is a no-op when the inquiry is already linked" do
    create(:persona_verification, identity: identity, persona_inquiry_id: inquiry_id)
    expect { perform }.not_to change(Verification, :count)
  end

  it "leaves a pending verification alone" do
    record = create(:identity_persona_record, identity: identity)
    create(:persona_verification, :pending, identity: identity, persona_record: record, persona_inquiry_id: record.inquiry_id)
    expect { perform }.not_to change(Verification, :count)
  end

  it "replaces a stale draft and expires its inquiry" do
    stale = create(:persona_verification, identity: identity)
    expect(mock_service).to receive(:expire_inquiry).with(stale.persona_inquiry_id)

    perform

    expect(Verification.exists?(stale.id)).to be(false)
    expect(identity.verifications.sole.persona_inquiry_id).to eq(inquiry_id)
  end
end
