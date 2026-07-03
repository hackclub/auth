require "rails_helper"

RSpec.describe "Two-factor enrollment gate", type: :request do
  let(:identity) { create(:identity, two_factor_required: true) }
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

  context "when the identity has no 2FA method enrolled" do
    it "redirects the home page to the security page" do
      get "/"

      expect(response).to redirect_to(security_path)
      expect(flash[:error]).to include("requires two-factor authentication")
    end

    it "blocks OAuth authorization" do
      get "/oauth/authorize"

      expect(response).to redirect_to(security_path)
    end

    it "responds to HTMX requests with an HX-Redirect header" do
      get "/", headers: { "HX-Request" => "true" }

      expect(response).to have_http_status(:ok)
      expect(response.headers["HX-Redirect"]).to eq(security_path)
    end

    it "allows the security page" do
      get "/security"

      expect(response).to have_http_status(:ok)
    end

    it "allows TOTP enrollment" do
      get "/identity_totps"

      expect(response).to have_http_status(:ok)
    end

    it "allows the authorized applications panel on the security page" do
      get "/authorized_applications", headers: { "HX-Request" => "true" }

      expect(response).to have_http_status(:ok)
      expect(response.headers["HX-Redirect"]).to be_nil
    end

    it "allows passkey enrollment" do
      get "/passkeys"

      expect(response).to have_http_status(:ok)
    end

    it "allows logging out" do
      delete "/logout"

      expect(response).to redirect_to(welcome_path)
    end
  end

  context "when the identity has a verified TOTP" do
    before do
      identity.totps.create!.mark_verified!
    end

    it "does not redirect" do
      get "/"

      expect(response).to have_http_status(:ok)
    end
  end

  context "when the identity does not have the override" do
    let(:identity) { create(:identity) }

    it "does not redirect" do
      get "/"

      expect(response).to have_http_status(:ok)
    end
  end
end
