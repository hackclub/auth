require "rails_helper"

RSpec.describe "Persona verification flow", type: :request do
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
    allow(Flipper).to receive(:enabled?).and_call_original
    allow(Flipper).to receive(:enabled?).with(:persona_verification_2026_04_09, identity).and_return(true)
    allow(Rails.application.credentials).to receive(:persona).and_return(mock_credentials)
  end

  describe "GET /verifications/new" do
    it "shows verification chooser for student-ID-eligible countries" do
      get "/verifications/new"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("verifications.choose.instant_title"))
      expect(response.body).to include(I18n.t("verifications.choose.student_id_title"))
    end

    it "redirects to persona for non-eligible countries" do
      identity.update!(country: "GB")

      get "/verifications/new"

      expect(response).to redirect_to(persona_verification_path)
    end

    it "redirects to document when flag is disabled" do
      allow(Flipper).to receive(:enabled?).with(:persona_verification_2026_04_09, identity).and_return(false)

      get "/verifications/new"

      expect(response).to redirect_to(verification_step_path(:document))
    end

    it "redirects to status when already pending" do
      create(:persona_verification, identity: identity, status: :pending)

      get "/verifications/new"

      expect(response).to redirect_to(verification_status_path)
    end
  end

  describe "GET /verifications/persona" do
    it "creates a draft persona verification and renders the page" do
      get "/verifications/persona"

      expect(response).to have_http_status(:ok)
      expect(identity.persona_verifications.draft.count).to eq(1)
    end

    it "reuses an existing draft verification" do
      create(:persona_verification, identity: identity, status: :draft)

      expect {
        get "/verifications/persona"
      }.not_to change(Verification::PersonaVerification, :count)

      expect(response).to have_http_status(:ok)
    end

    it "resumes an existing inquiry with a fresh session token" do
      verification = create(:persona_verification, identity: identity, status: :draft,
        persona_inquiry_id: "inq_existing_123", persona_session_token: "old_token")

      get "/verifications/persona"

      expect(response).to have_http_status(:ok)
      verification.reload
      expect(verification.persona_session_token).not_to eq("old_token")
    end

    it "includes inquiry_id and session_token in the response body" do
      get "/verifications/persona"

      expect(response.body).to include("data-inquiry-id")
      expect(response.body).to include("data-session-token")
    end

    it "redirects to status when already verified" do
      create(:persona_verification, identity: identity, status: :approved)

      get "/verifications/persona"

      expect(response).to redirect_to(verification_status_path)
    end

    it "shows error when persona API fails" do
      mock_service = instance_double(Persona::MockAPIService)
      allow(Persona).to receive(:instance).and_return(mock_service)
      allow(mock_service).to receive(:create_inquiry).and_raise(Persona::APIError, "connection refused")

      get "/verifications/persona"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("verification provider")
    end
  end
end
