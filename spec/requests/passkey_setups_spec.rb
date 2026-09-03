require "rails_helper"

RSpec.describe "PasskeySetups", type: :request do
  let(:identity) { create(:identity) }
  let(:identity_session) do
    identity.sessions.create!(
      session_token: SecureRandom.hex(32),
      expires_at: 1.week.from_now
    )
  end

  before do
    allow_any_instance_of(ApplicationController).to receive(:current_identity).and_return(identity)
    allow_any_instance_of(ApplicationController).to receive(:current_session).and_return(identity_session)
    allow_any_instance_of(ApplicationController).to receive(:identity_signed_in?).and_return(true)
  end

  describe "GET /passkey/setup" do
    it "renders the setup prompt for an eligible identity" do
      get passkey_setup_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Sign in faster with a passkey")
      expect(response.body).to include("setup-registration-form")
      expect(response.body).to include("show again")
      expect(response.body).to include("Skip")
      expect(response.body).to include("auth-page")
    end

    it "redirects to the return_to when the identity already has a passkey" do
      identity.webauthn_credentials.create!(
        webauthn_id: SecureRandom.random_bytes(32),
        webauthn_public_key: SecureRandom.random_bytes(65)
      )

      get passkey_setup_path, params: { return_to: "/security" }

      expect(response).to redirect_to("/security")
    end

    it "redirects to root when the promotion has been dismissed" do
      identity.dismiss_passkey_promotion!

      get passkey_setup_path

      expect(response).to redirect_to(root_path)
    end
  end

  describe "POST /passkeys/options" do
    it "allows registration without a step-up when the session is recent" do
      post options_identity_webauthn_credentials_path

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to include("challenge")
    end
  end

  describe "POST /passkey/setup/skip" do
    it "dismisses for the session and redirects to the return_to" do
      post passkey_setup_skip_path, params: { return_to: "/" }

      expect(session[:passkey_promotion_dismissed]).to be true
      expect(response).to redirect_to("/")
    end

    it "does not persist the dismissal" do
      post passkey_setup_skip_path, params: { return_to: "/" }

      expect(identity.reload.passkey_prompt_dismissed_at).to be_nil
    end

    it "persists the dismissal when the don't show again toggle is checked" do
      post passkey_setup_skip_path, params: { return_to: "/", dont_show_again: "true" }

      expect(identity.reload.passkey_prompt_dismissed_at).to be_present
      expect(response).to redirect_to("/")
    end
  end
end
