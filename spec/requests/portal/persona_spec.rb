require "rails_helper"

RSpec.describe "Portal persona verification", type: :request do
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
    Flipper.enable(:persona_verification_2026_04_09, identity)
    allow(Rails.application.credentials).to receive(:persona).and_return(mock_credentials)
  end

  after { Flipper.disable(:persona_verification_2026_04_09) }

  describe "document gate for persona-flagged users" do
    describe "GET /portal/verify/document" do
      it "redirects persona-flagged users to persona page" do
        get "/portal/verify/document"
        expect(response).to redirect_to(portal_verify_persona_path)
      end

      it "includes flash message about automated verification" do
        get "/portal/verify/document"
        expect(flash[:info]).to include("automated verification")
      end
    end

    describe "POST /portal/verify/document" do
      it "redirects persona-flagged users to persona page" do
        post "/portal/verify/document", params: {
          identity_document: { document_type: "government_id", files: [] }
        }
        expect(response).to redirect_to(portal_verify_persona_path)
      end
    end
  end

  describe "GET /portal/verify/persona" do
    it "renders the persona verification page" do
      get "/portal/verify/persona"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("data-inquiry-id")
      expect(response.body).to include("data-session-token")
    end

    it "creates a draft verification" do
      expect {
        get "/portal/verify/persona"
      }.to change(Verification::PersonaVerification, :count).by(1)

      expect(identity.persona_verifications.draft.count).to eq(1)
    end

    it "redirects when already verified" do
      create(:persona_verification, :approved, identity: identity)
      get "/portal/verify/persona"

      expect(response).to have_http_status(:redirect)
    end

    it "redirects when verification is pending" do
      create(:persona_verification, :pending, identity: identity)
      get "/portal/verify/persona"

      expect(response).to have_http_status(:redirect)
    end
  end
end
