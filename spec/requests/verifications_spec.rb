require "rails_helper"

RSpec.describe "Verifications", type: :request do
  let(:identity) { create(:identity) }
  let(:session) do
    identity.sessions.create!(
      session_token: SecureRandom.hex(32),
      expires_at: 1.week.from_now
    )
  end
  let(:mock_credentials) do
    double(template_id: "itmpl_test_abc", api_key: "persona_sandbox_test", webhook_secret: "whsec_test")
  end

  before do
    allow_any_instance_of(ApplicationController).to receive(:current_identity).and_return(identity)
    allow_any_instance_of(ApplicationController).to receive(:current_session).and_return(session)
    allow_any_instance_of(ApplicationController).to receive(:identity_signed_in?).and_return(true)
    allow(Rails.application.credentials).to receive(:persona).and_return(mock_credentials)
  end

  describe "GET /verifications/status" do
    it "shows processing when a draft persona verification exists" do
      Flipper.enable(:persona_verification_2026_04_09, identity)
      create(:persona_verification, identity: identity, status: :draft)

      get verification_status_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Your ID is being checked")
    ensure
      Flipper.disable(:persona_verification_2026_04_09)
    end

    it "shows not started when no verifications exist" do
      get verification_status_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("not started").or include("Not started").or include("not_started")
    end
  end

  describe "document gate for persona-flagged users" do
    before do
      Flipper.enable(:persona_verification_2026_04_09, identity)
    end

    after do
      Flipper.disable(:persona_verification_2026_04_09)
    end

    describe "GET /verifications/document (show)" do
      it "redirects persona-flagged users to persona page" do
        get verification_step_path(:document)
        expect(response).to redirect_to(persona_verification_path)
      end

      it "shows flash message about automated verification" do
        get verification_step_path(:document)
        follow_redirect!
        expect(flash[:info]).to include("automated verification")
      end
    end

    describe "PUT /verifications/document (update)" do
      it "redirects persona-flagged users to persona page" do
        put update_verification_step_path(:document), params: {
          identity_document: { document_type: "government_id", files: [] }
        }
        expect(response).to redirect_to(persona_verification_path)
      end
    end
  end

  describe "persona verification attempt cap" do
    before do
      Flipper.enable(:persona_verification_2026_04_09, identity)
    end

    after do
      Flipper.disable(:persona_verification_2026_04_09)
    end

    let(:rejected_attrs) { { status: :rejected, rejection_reason: "info_mismatch" } }

    context "when identity is persona-locked" do
      before do
        create_list(:persona_verification, Identity::MAX_PERSONA_ATTEMPTS, identity: identity, **rejected_attrs)
      end

      it "redirects GET /verifications/new to status" do
        get new_verifications_path
        expect(response).to redirect_to(verification_status_path)
      end

      it "redirects GET /verifications/persona to status" do
        get persona_verification_path
        expect(response).to redirect_to(verification_status_path)
      end

      it "redirects GET /verifications/student_id to status" do
        get student_id_verification_path
        expect(response).to redirect_to(verification_status_path)
      end

      it "shows locked message on status page" do
        get verification_status_path
        expect(response.body).to include("Let&#39;s get you verified")
        expect(response.body).to include("identity@hackclub.com")
      end
    end

    context "when identity has attempts remaining" do
      before do
        create_list(:persona_verification, 1, identity: identity, **rejected_attrs)
        allow(Persona).to receive(:instance).and_return(Persona::MockAPIService.new)
      end

      it "allows access to persona verification" do
        get persona_verification_path
        expect(response).to have_http_status(:ok)
      end
    end
  end
end
