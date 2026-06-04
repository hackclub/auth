require "rails_helper"

RSpec.describe Persona::ProcessInquiryEventJob, type: :job do
  let(:identity) { create(:identity) }
  let(:verification) { create(:persona_verification, identity: identity) }
  let(:inquiry_id) { verification.persona_inquiry_id }

  let(:mock_service) { instance_double(Persona::APIService) }
  let(:gov_id_verification) do
    Persona::GovernmentIdVerification.new(
      id: "ver_gov123", status: "passed",
      name_first: "HEIDI", name_last: "TRASHWORTH",
      birthdate: Date.parse("2010-06-15"), country_code: "US",
      id_class: "dl", expiration_date: Date.parse("2029-06-15"),
      entity_confidence_score: 0.98,
      checks: [ { "name" => "id_entity_detection", "status" => "passed", "reasons" => [], "requirement" => "required" } ],
      front_photo: { url: "https://files.withpersona.com/front.jpg?access_token=tok123", filename: "front.jpg" },
      back_photo: { url: "https://files.withpersona.com/back.jpg?access_token=tok456", filename: "back.jpg" },
      selfie_photo: nil,
      raw: { name_first: "HEIDI", name_middle: "J", name_last: "TRASHWORTH",
             document_number: "D1234567", address_street_1: "123 TEST ST",
             address_city: "SAN FRANCISCO", address_subdivision: "California" }
    )
  end
  let(:inquiry_data) do
    Persona::Inquiry.new(
      id: inquiry_id,
      status: "completed",
      account_id: "act_xyz789",
      session_token: nil,
      verification_ids: [
        { type: "verification/government-id", id: "ver_gov123" },
        { type: "verification/selfie", id: "ver_selfie456" }
      ],
      document_ids: [ { type: "document/government-id", id: "doc_gov123" } ],
      behaviors: { "behavior_threat_level" => "low", "bot_score" => 8 },
      sessions: [ { is_tor: false, is_proxy: false, threat_level: "low", country_code: "US" } ],
      raw: { status: "completed", behaviors: { "behavior_threat_level" => "low", "bot_score" => 8 } }
    )
  end

  let(:document_photos) do
    Persona::PhotoSet.new(
      document: [
        { filename: "front.jpg", url: "https://files.withpersona.com/front.jpg?access_token=tok123", byte_size: 12345, label: "front" },
        { filename: "back.jpg", url: "https://files.withpersona.com/back.jpg?access_token=tok456", byte_size: 12345, label: "back" }
      ],
      liveness: []
    )
  end

  let(:selfie_photos) do
    Persona::PhotoSet.new(
      document: [],
      liveness: [
        { url: "https://files.withpersona.com/center.jpg?access_token=mock", label: "selfie_center" },
        { url: "https://files.withpersona.com/left.jpg?access_token=mock", label: "selfie_left" }
      ]
    )
  end

  before do
    allow(Persona).to receive(:instance).and_return(mock_service)
    allow(mock_service).to receive(:retrieve_inquiry).and_return(inquiry_data)
    allow(mock_service).to receive(:retrieve_government_id_verification).and_return(gov_id_verification)
    allow(mock_service).to receive(:retrieve_document_photos).and_return(document_photos)
    allow(mock_service).to receive(:retrieve_verification_photos).with("ver_gov123", type: "verification/government-id").and_return(Persona::PhotoSet.empty)
    allow(mock_service).to receive(:retrieve_verification_photos).with("ver_selfie456", type: "verification/selfie").and_return(selfie_photos)
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

    it "creates one Identity::Document with all photos attached" do
      expect {
        described_class.perform_now(event_name: event_name, inquiry_id: inquiry_id)
      }.to change(Identity::Document, :count).by(1)

      doc = Identity::Document.last
      expect(doc.document_type).to eq("persona_gov_id")
      expect(doc.identity).to eq(identity)
      expect(doc.files).to be_attached
      expect(doc.files.count).to eq(4) # front + back + 2 selfies
    end

    it "links the persona record and document to the verification" do
      described_class.perform_now(event_name: event_name, inquiry_id: inquiry_id)

      verification.reload
      expect(verification.persona_record).to be_present
      expect(verification.identity_document).to be_present
      expect(verification.identity_document).to be_persona_gov_id
    end

    it "transitions the verification to pending" do
      described_class.perform_now(event_name: event_name, inquiry_id: inquiry_id)

      verification.reload
      expect(verification).to be_pending
    end

    it "does not enqueue the pipeline job (that fires on approved)" do
      expect {
        described_class.perform_now(event_name: event_name, inquiry_id: inquiry_id)
      }.not_to have_enqueued_job(Persona::VerificationPipelineJob)
    end

    context "when photo downloads fail" do
      before do
        allow(mock_service).to receive(:download_file).and_raise(Persona::APIError, "failed to download file (400)")
      end

      it "still transitions to pending" do
        described_class.perform_now(event_name: event_name, inquiry_id: inquiry_id)

        verification.reload
        expect(verification).to be_pending
      end

      it "still saves the PersonaRecord" do
        expect {
          described_class.perform_now(event_name: event_name, inquiry_id: inquiry_id)
        }.to change(Identity::PersonaRecord, :count).by(1)
      end

      it "reports to Sentry" do
        expect(Sentry).to receive(:capture_exception).at_least(:once)
        described_class.perform_now(event_name: event_name, inquiry_id: inquiry_id)
      end
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

    it "enqueues the verification pipeline job" do
      expect {
        described_class.perform_now(event_name: event_name, inquiry_id: inquiry_id)
      }.to have_enqueued_job(Persona::VerificationPipelineJob).with(verification)
    end

    it "creates an activity" do
      described_class.perform_now(event_name: event_name, inquiry_id: inquiry_id)
      expect(PublicActivity::Activity.where(trackable: verification).where("key LIKE ?", "%persona_inquiry_approved%")).to exist
    end

    context "when approved arrives before completed finishes (race condition)" do
      before do
        verification.update!(status: "draft", persona_record: nil, identity_document: nil)
      end

      it "runs completed first, then enqueues the pipeline" do
        expect {
          described_class.perform_now(event_name: "inquiry.approved", inquiry_id: inquiry_id)
        }.to have_enqueued_job(Persona::VerificationPipelineJob)

        verification.reload
        expect(verification.persona_record).to be_present
        expect(verification.identity_document).to be_present
      end
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

    it "creates an activity" do
      described_class.perform_now(event_name: event_name, inquiry_id: inquiry_id)
      expect(PublicActivity::Activity.where(trackable: verification).where("key LIKE ?", "%marked_for_review%")).to exist
    end
  end

  describe "inquiry.failed" do
    let(:event_name) { "inquiry.failed" }

    it "rejects the verification with too_many_attempts" do
      described_class.perform_now(event_name: event_name, inquiry_id: inquiry_id)

      verification.reload
      expect(verification).to be_rejected
      expect(verification.rejection_reason).to eq("too_many_attempts")
      expect(verification).not_to be_fatal
    end
  end

  describe "inquiry.expired" do
    let(:event_name) { "inquiry.expired" }

    it "rejects the verification with inquiry_expired" do
      described_class.perform_now(event_name: event_name, inquiry_id: inquiry_id)

      verification.reload
      expect(verification).to be_rejected
      expect(verification.rejection_reason).to eq("inquiry_expired")
      expect(verification).not_to be_fatal
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
