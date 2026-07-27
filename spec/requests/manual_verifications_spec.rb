require "rails_helper"

RSpec.describe "Manual verifications", type: :request do
  let(:identity) { create(:identity) }
  let(:session) do
    identity.sessions.create!(
      session_token: SecureRandom.hex(32),
      expires_at: 1.week.from_now
    )
  end

  before do
    allow_any_instance_of(ApplicationController).to receive(:current_identity).and_return(identity)
    allow_any_instance_of(ApplicationController).to receive(:current_session).and_return(session)
    allow_any_instance_of(ApplicationController).to receive(:identity_signed_in?).and_return(true)
  end

  after { Flipper.disable(VerificationCase::FLIPPER_FLAG) }

  describe "gating" do
    it "bounces users without the flipper flag" do
      get manual_verification_path
      expect(response).to redirect_to(root_path)
    end

    it "bounces flagged users with no open case" do
      Flipper.enable(VerificationCase::FLIPPER_FLAG, identity)
      get manual_verification_path
      expect(response).to redirect_to(root_path)
    end

    it "requires the single-use token on first visit" do
      kase = create(:verification_case, identity: identity, status: :link_sent)
      kase.generate_access_token!
      Flipper.enable(VerificationCase::FLIPPER_FLAG, identity)

      get manual_verification_path
      expect(response).to have_http_status(:forbidden)
    end

    it "consumes a valid token then allows session access" do
      kase = create(:verification_case, identity: identity, status: :link_sent)
      token = kase.generate_access_token!
      Flipper.enable(VerificationCase::FLIPPER_FLAG, identity)

      get manual_verification_path(token: token)
      expect(response).to redirect_to(manual_verification_path)
      expect(kase.reload.access_token_used_at).to be_present

      get manual_verification_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "the flow" do
    let(:kase) do
      create(:verification_case, identity: identity, status: :link_sent,
        access_token_used_at: Time.current)
    end

    before do
      kase
      Flipper.enable(VerificationCase::FLIPPER_FLAG, identity)
    end

    it "shows document class selection first" do
      get manual_verification_path
      expect(response.body).to include("Which describes you?")
    end

    it "records government ID selection" do
      post manual_verification_document_class_path, params: { document_class: "government_id" }
      expect(kase.reload.document_class).to eq("government_id")
      expect(kase.events.where(key: "document_class_selected")).to exist
    end

    it "nudges the alternative path once before accepting" do
      post manual_verification_document_class_path, params: { document_class: "alternative", alternative_reason: "no_government_id" }
      expect(response.body).to include("One more thing")
      expect(kase.reload.document_class).to be_nil

      post manual_verification_document_class_path, params: { document_class: "alternative", alternative_reason: "no_government_id", nudge_confirmed: "true" }
      expect(kase.reload.document_class).to eq("alternative")
    end

    it "requires attestation and biometric consent to submit documents" do
      kase.update!(document_class: "government_id")

      post manual_verification_documents_path, params: {
        primary_doc: fixture_file_upload_for("doc.pdf"),
        legal_name: "Heidi Trashworth"
      }
      expect(kase.reload).to be_link_sent # not advanced
    end

    it "accepts a government ID direct upload and advances the case" do
      kase.update!(document_class: "government_id")

      post manual_verification_documents_path, params: {
        primary_doc: fixture_file_upload_for("doc.pdf"),
        attested: "1", biometric_consent: "1",
        legal_name: "Heidi Trashworth", date_of_birth: "2008-04-01",
        document_type: "passport", issuing_authority: "Romania"
      }

      kase.reload
      expect(kase).to be_docs_submitted
      expect(kase.attested).to be(true)
      expect(kase.biometric_consent).to be(true)
      expect(kase.submitted_fields["legal_name"]).to eq("Heidi Trashworth")
      expect(kase.documents.count).to eq(1)
    end

    it "requires camera-only document AND selfie on a skip-persona case" do
      kase.update!(document_class: "government_id", skip_persona: true)
      base_params = {
        attested: "1", biometric_consent: "1",
        legal_name: "Heidi Trashworth", date_of_birth: "2008-04-01",
        document_type: "passport", issuing_authority: "Romania"
      }

      # pdf blocked — camera JPEG/PNG only
      post manual_verification_documents_path, params: base_params.merge(
        primary_doc: fixture_file_upload_for("doc.pdf"),
        selfie: camera_capture_upload("selfie-capture.jpg")
      )
      expect(kase.reload).to be_link_sent

      # selfie missing — blocked
      post manual_verification_documents_path, params: base_params.merge(
        primary_doc: camera_capture_upload("document-capture.jpg")
      )
      expect(kase.reload).to be_link_sent

      # both camera captures — accepted, selfie stored as its own document
      post manual_verification_documents_path, params: base_params.merge(
        primary_doc: camera_capture_upload("document-capture.jpg"),
        selfie: camera_capture_upload("selfie-capture.jpg")
      )
      kase.reload
      expect(kase).to be_docs_submitted
      expect(kase.documents.where(document_kind: "selfie").count).to eq(1)
      expect(kase.selfie_available?).to be(true)
    end

    it "keeps skip-persona cases away from the persona capture flow" do
      kase.update!(document_class: "government_id", skip_persona: true)

      get manual_verification_capture_path
      expect(response).to redirect_to(manual_verification_path)
      expect(kase.reload.persona_inquiry_id).to be_nil
    end

    it "gates the booking link behind the recording acknowledgment" do
      kase.update!(document_class: "government_id", status: :docs_submitted)
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("CALCOM_MANUAL_VERIFICATION_BOOKING_URL").and_return("https://cal.example.com/verify")

      get manual_verification_path
      expect(response.body).to include("verification calls are recorded")
      expect(response.body).not_to include("https://cal.example.com/verify")

      post manual_verification_recording_ack_path
      get manual_verification_path
      expect(response.body).to include("https://cal.example.com/verify")
    end
  end

  def fixture_file_upload_for(name)
    Rack::Test::UploadedFile.new(StringIO.new("fake pdf bytes"), "application/pdf", original_filename: name)
  end

  def camera_capture_upload(name)
    Rack::Test::UploadedFile.new(StringIO.new("fake jpeg bytes"), "image/jpeg", original_filename: name)
  end
end
