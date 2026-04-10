require "rails_helper"

RSpec.describe Persona::ProcessInquiryEventJob, type: :job do
  let(:identity) { create(:identity) }
  let(:verification) { create(:persona_verification, identity: identity) }
  let(:inquiry_id) { verification.persona_inquiry_id }

  let(:mock_service) { instance_double(Persona::APIService) }
  let(:gov_id_verification) do
    Persona::GovernmentIdVerification.new(
      id: "ver_gov123",
      status: "passed",
      name_first: "HEIDI",
      name_last: "TRASHWORTH",
      birthdate: Date.parse("2010-06-15"),
      country_code: "US",
      front_photo: { "url" => "https://files.withpersona.com/front.jpg", "filename" => "front.jpg" },
      back_photo: { "url" => "https://files.withpersona.com/back.jpg", "filename" => "back.jpg" },
      selfie_photo: nil
    )
  end
  let(:inquiry_data) do
    Persona::Inquiry.new(
      id: inquiry_id,
      status: "completed",
      account_id: "act_xyz789",
      session_token: nil
    )
  end

  before do
    allow(Persona).to receive(:instance).and_return(mock_service)
    allow(mock_service).to receive(:retrieve_inquiry).and_return(inquiry_data)
    allow(mock_service).to receive(:retrieve_government_id_verification).and_return(gov_id_verification)
    allow(mock_service).to receive(:download_file).and_return(StringIO.new("fake image data"))
  end

  describe "inquiry.completed" do
    let(:event_name) { "inquiry.completed" }

    it "creates an Identity::PersonaRecord with correct attributes" do
      expect {
        described_class.perform_now(event_name: event_name, inquiry_id: inquiry_id)
      }.to change(Identity::PersonaRecord, :count).by(1)

      record = Identity::PersonaRecord.last
      expect(record.identity).to eq(identity)
      expect(record.inquiry_id).to eq(inquiry_id)
      expect(record.name_first).to eq("HEIDI")
      expect(record.name_last).to eq("TRASHWORTH")
      expect(record.birthdate).to eq(Date.parse("2010-06-15"))
      expect(record.country_code).to eq("US")
    end

    it "creates an Identity::Document with front and back photos attached" do
      expect {
        described_class.perform_now(event_name: event_name, inquiry_id: inquiry_id)
      }.to change(Identity::Document, :count).by(1)

      doc = Identity::Document.last
      expect(doc.document_type).to eq("persona_gov_id")
      expect(doc.identity).to eq(identity)
      expect(doc.files).to be_attached
    end

    it "links the persona record and document to the verification" do
      described_class.perform_now(event_name: event_name, inquiry_id: inquiry_id)

      verification.reload
      expect(verification.persona_record).to be_present
      expect(verification.identity_document).to be_present
    end

    it "transitions the verification to pending" do
      described_class.perform_now(event_name: event_name, inquiry_id: inquiry_id)

      verification.reload
      expect(verification).to be_pending
    end

    it "enqueues NoticeResemblancesJob" do
      expect {
        described_class.perform_now(event_name: event_name, inquiry_id: inquiry_id)
      }.to have_enqueued_job(Identity::NoticeResemblancesJob)
    end

    it "enqueues CheckDiscrepanciesJob" do
      expect {
        described_class.perform_now(event_name: event_name, inquiry_id: inquiry_id)
      }.to have_enqueued_job(Verification::CheckDiscrepanciesJob)
    end
  end

  describe "inquiry.approved" do
    let(:event_name) { "inquiry.approved" }

    before do
      # Set up a pending verification with a persona record
      persona_record = create(:identity_persona_record,
        identity: identity,
        inquiry_id: inquiry_id,
        birthdate: Date.parse("2010-06-15"))
      verification.update!(
        status: "pending",
        persona_record: persona_record,
        identity_document: create(:identity_document, identity: identity)
      )
    end

    it "transitions the verification to approved" do
      described_class.perform_now(event_name: event_name, inquiry_id: inquiry_id)

      verification.reload
      expect(verification).to be_approved
    end

    it "sets ysws_eligible to true when 13 <= age <= 19" do
      described_class.perform_now(event_name: event_name, inquiry_id: inquiry_id)

      identity.reload
      expect(identity.ysws_eligible).to be true
    end

    it "sets ysws_eligible to false when age > 19" do
      verification.persona_record.update!(birthdate: Date.parse("2000-01-01"))

      described_class.perform_now(event_name: event_name, inquiry_id: inquiry_id)

      identity.reload
      expect(identity.ysws_eligible).to be false
    end

    it "sends the approved mailer" do
      expect {
        described_class.perform_now(event_name: event_name, inquiry_id: inquiry_id)
      }.to have_enqueued_mail(VerificationMailer, :approved)
    end
  end

  describe "inquiry.declined" do
    let(:event_name) { "inquiry.declined" }

    before do
      persona_record = create(:identity_persona_record,
        identity: identity,
        inquiry_id: inquiry_id)
      verification.update!(
        status: "pending",
        persona_record: persona_record,
        identity_document: create(:identity_document, identity: identity)
      )
    end

    it "transitions the verification to rejected" do
      described_class.perform_now(event_name: event_name, inquiry_id: inquiry_id)

      verification.reload
      expect(verification).to be_rejected
    end

    it "sets a rejection reason" do
      described_class.perform_now(event_name: event_name, inquiry_id: inquiry_id)

      verification.reload
      expect(verification.rejection_reason).to be_present
    end
  end

  describe "inquiry.marked_for_review" do
    let(:event_name) { "inquiry.marked_for_review" }

    before do
      persona_record = create(:identity_persona_record,
        identity: identity,
        inquiry_id: inquiry_id)
      verification.update!(
        status: "pending",
        persona_record: persona_record
      )
    end

    it "does not change the verification status" do
      expect {
        described_class.perform_now(event_name: event_name, inquiry_id: inquiry_id)
      }.not_to change { verification.reload.status }
    end
  end

  describe "idempotency" do
    let(:event_name) { "inquiry.completed" }

    it "is a no-op when the event has already been processed" do
      # Process once
      described_class.perform_now(event_name: event_name, inquiry_id: inquiry_id)

      # Process again — should not create duplicates or raise
      expect {
        described_class.perform_now(event_name: event_name, inquiry_id: inquiry_id)
      }.not_to change(Identity::PersonaRecord, :count)
    end

    it "does not raise on duplicate approval" do
      persona_record = create(:identity_persona_record,
        identity: identity,
        inquiry_id: inquiry_id)
      verification.update!(
        status: "pending",
        persona_record: persona_record,
        identity_document: create(:identity_document, identity: identity)
      )

      described_class.perform_now(event_name: "inquiry.approved", inquiry_id: inquiry_id)

      # Second delivery should be a no-op, not raise
      expect {
        described_class.perform_now(event_name: "inquiry.approved", inquiry_id: inquiry_id)
      }.not_to raise_error
    end
  end
end
