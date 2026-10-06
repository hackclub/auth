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

  describe "after withdrawal" do
    it "shows the invalid-link page to a user following the old emailed link" do
      kase = create(:verification_case, identity: identity, status: :link_sent)
      token = kase.generate_access_token!
      Flipper.enable(VerificationCase::FLIPPER_FLAG, identity)

      kase.withdraw!

      get manual_verification_path(token: token)
      expect(response).to have_http_status(:forbidden)
      expect(response.body).to include("This link isn't valid")
    end

    it "bounces a plain visit (no token) to the home page" do
      kase = create(:verification_case, identity: identity, status: :link_sent, access_token_used_at: Time.current)
      kase.withdraw!

      get manual_verification_path
      expect(response).to redirect_to(root_path)
    end
  end

  describe "after a redo request" do
    it "puts the user back at document submission, needing the new link first" do
      kase = create(:verification_case, identity: identity, status: :docs_submitted, document_class: "government_id",
        access_token_used_at: 1.hour.ago)
      Flipper.enable(VerificationCase::FLIPPER_FLAG, identity)
      kase.request_redo!
      token = kase.rotate_access_link!(reopen_gate: true)

      get manual_verification_path
      expect(response).to have_http_status(:forbidden)

      get manual_verification_path(token: token)
      expect(response).to redirect_to(manual_verification_path)

      get manual_verification_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Submit your document")
      expect(response.body).not_to include("Book your call")
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

    describe "non-file values in the upload fields" do
      let(:base_params) do
        {
          attested: "1", biometric_consent: "1",
          legal_name: "Heidi Trashworth", date_of_birth: "2008-04-01",
          document_type: "passport", issuing_authority: "Romania"
        }
      end

      it "rejects a plain string document on a normal case without crashing" do
        kase.update!(document_class: "government_id")

        post manual_verification_documents_path, params: base_params.merge(primary_doc: "not-a-file")

        expect(response).to redirect_to(manual_verification_path)
        expect(flash[:error]).to match(/choose a file/)
        expect(kase.reload).to be_link_sent
        expect(kase.documents.count).to eq(0)
      end

      it "rejects a plain string document on a skip-persona case without crashing" do
        kase.update!(document_class: "government_id", skip_persona: true)

        post manual_verification_documents_path, params: base_params.merge(
          primary_doc: "not-a-file",
          selfie: camera_capture_upload("selfie-capture.jpg")
        )

        expect(response).to redirect_to(manual_verification_path)
        expect(flash[:error]).to match(/choose a file/)
        expect(kase.reload).to be_link_sent
        expect(kase.documents.count).to eq(0)
      end

      it "rejects a plain string selfie on a skip-persona case without crashing" do
        kase.update!(document_class: "government_id", skip_persona: true)

        post manual_verification_documents_path, params: base_params.merge(
          primary_doc: camera_capture_upload("document-capture.jpg"),
          selfie: "not-a-file"
        )

        expect(response).to redirect_to(manual_verification_path)
        expect(flash[:error]).to match(/choose a file/)
        expect(kase.reload).to be_link_sent
        expect(kase.documents.count).to eq(0)
      end

      it "treats an empty-string document as missing" do
        kase.update!(document_class: "government_id")

        post manual_verification_documents_path, params: base_params.merge(primary_doc: "")

        expect(response).to redirect_to(manual_verification_path)
        expect(flash[:error]).to match(/document is required/)
        expect(kase.reload).to be_link_sent
        expect(kase.documents.count).to eq(0)
      end

      it "rejects a zero-byte upload" do
        kase.update!(document_class: "government_id")

        post manual_verification_documents_path, params: base_params.merge(
          primary_doc: Rack::Test::UploadedFile.new(StringIO.new(""), "application/pdf", original_filename: "empty.pdf")
        )

        expect(response).to redirect_to(manual_verification_path)
        expect(flash[:error]).to match(/empty/)
        expect(kase.reload).to be_link_sent
        expect(kase.documents.count).to eq(0)
      end
    end

    describe "persona capture prerequisites" do
      let(:details) do
        { legal_name: "Heidi Trashworth", date_of_birth: "2008-04-01",
          document_type: "passport", issuing_authority: "Romania" }
      end

      before do
        kase.update!(document_class: "government_id")
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("PERSONA_MANUAL_CAPTURE_TEMPLATE").and_return("itmpl_test123")
      end

      it "offers the scan button inside the same form as the details and consent" do
        get manual_verification_path
        expect(response.body).to include("Scan with your camera")
        expect(response.body).to include(manual_verification_prepare_capture_path)
        expect(response.body).to include('name="biometric_consent"')
      end

      it "refuses to start the capture before anything was recorded on the case" do
        expect(Persona).not_to receive(:instance)

        get manual_verification_capture_path
        expect(response).to redirect_to(manual_verification_path)
        expect(flash[:error]).to match(/before scanning/)
        expect(kase.reload.persona_inquiry_id).to be_nil
      end

      it "requires attestation and biometric consent to prepare the capture" do
        post manual_verification_prepare_capture_path, params: details.merge(attested: "1")
        expect(response).to redirect_to(manual_verification_path)
        expect(flash[:error]).to match(/consent checkbox/)

        kase.reload
        expect(kase.attested).to be(false)
        expect(kase.biometric_consent).to be(false)
        expect(kase.submitted_fields).to be_empty
      end

      it "requires the same submitted fields as the direct upload" do
        post manual_verification_prepare_capture_path, params: { attested: "1", biometric_consent: "1", legal_name: "Heidi Trashworth" }
        expect(response).to redirect_to(manual_verification_path)
        expect(flash[:error]).to match(/Date of birth, Document type, and Issuing authority are required/)
        expect(kase.reload.submitted_fields).to be_empty
      end

      it "records the prerequisites on the case, then lets the capture start" do
        post manual_verification_prepare_capture_path, params: details.merge(attested: "1", biometric_consent: "1")
        expect(response).to redirect_to(manual_verification_capture_path)

        kase.reload
        expect(kase.attested).to be(true)
        expect(kase.biometric_consent).to be(true)
        expect(kase.submitted_fields).to eq(details.transform_keys(&:to_s))
        expect(kase).to be_link_sent
        expect(kase.events.find_by(key: "capture_prerequisites_recorded").data["fields"]).to match_array(details.keys.map(&:to_s))

        service = instance_double(Persona::APIService)
        allow(Persona).to receive(:instance).and_return(service)
        allow(service).to receive(:create_inquiry).and_return(
          Persona::Inquiry.new(id: "inq_case_new", status: "created", account_id: nil, session_token: "sess_tok",
            verification_ids: [], document_ids: [], behaviors: {}, sessions: [], raw: {})
        )

        get manual_verification_capture_path
        expect(response).to have_http_status(:ok)
        expect(kase.reload.persona_inquiry_id).to eq("inq_case_new")
        # the capture template's prefill keys are underscored, not hyphenated
        expect(service).to have_received(:create_inquiry).with(
          hash_including(fields: hash_including(:name_first, :name_last, :email_address))
        )
      end

      it "keeps the direct upload path requiring the same fields" do
        post manual_verification_documents_path, params: {
          primary_doc: fixture_file_upload_for("doc.pdf"), attested: "1", biometric_consent: "1",
          legal_name: "Heidi Trashworth", date_of_birth: "2008-04-01"
        }
        expect(flash[:error]).to match(/Document type and Issuing authority are required/)
        expect(kase.reload).to be_link_sent
      end
    end

    it "keeps skip-persona cases away from the persona capture flow" do
      kase.update!(document_class: "government_id", skip_persona: true)

      get manual_verification_capture_path
      expect(response).to redirect_to(manual_verification_path)
      expect(kase.reload.persona_inquiry_id).to be_nil
    end

    it "redirects the legacy verification pages to the open case" do
      get verification_status_path
      expect(response).to redirect_to(manual_verification_path)

      get portal_verify_document_path
      expect(response).to redirect_to(manual_verification_path)
    end

    it "gates the booking link behind the call-capture acknowledgment" do
      kase.update!(document_class: "government_id", status: :docs_submitted)
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("CALCOM_MANUAL_VERIFICATION_BOOKING_URL").and_return("https://cal.example.com/verify")

      get manual_verification_path
      expect(response.body).to include("calls are not recorded")
      expect(response.body).not_to include("https://cal.example.com/verify")

      post manual_verification_call_capture_ack_path
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
