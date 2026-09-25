require "rails_helper"

RSpec.describe "PasskeyLogins", type: :request do
  describe "POST /passkey/login/options" do
    it "returns authentication options with a challenge" do
      post passkey_login_options_path

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["challenge"]).to be_present
    end
  end

  describe "POST /passkey/login/verify" do
    let(:identity) { create(:identity) }

    context "when the passkey verifies" do
      before do
        credential = identity.webauthn_credentials.create!(
          webauthn_id: SecureRandom.random_bytes(32),
          webauthn_public_key: SecureRandom.random_bytes(65)
        )
        allow_any_instance_of(PasskeyLoginsController)
          .to receive(:find_and_verify_discoverable_webauthn_credential)
          .and_return(credential)
      end

      it "signs the user in and redirects to the root path" do
        expect {
          post passkey_login_verify_path, params: { credential_data: "{}" }
        }.to change { identity.sessions.count }.by(1)

        expect(response).to redirect_to(root_path)
        expect(flash[:success]).to eq("Logged in!")
      end

      it "redirects to a safe return_to" do
        post passkey_login_verify_path, params: { credential_data: "{}", return_to: "/oauth/authorize?client_id=x" }

        expect(response).to redirect_to("/oauth/authorize?client_id=x")
      end

      it "ignores an unsafe return_to" do
        post passkey_login_verify_path, params: { credential_data: "{}", return_to: "https://evil.example.com" }

        expect(response).to redirect_to(root_path)
      end
    end

    context "when the passkey does not verify" do
      before do
        allow_any_instance_of(PasskeyLoginsController)
          .to receive(:find_and_verify_discoverable_webauthn_credential)
          .and_return(nil)
      end

      it "redirects back to login with an error and no session" do
        expect {
          post passkey_login_verify_path, params: { credential_data: "{}" }
        }.not_to change { IdentitySession.count }

        expect(response).to redirect_to(login_path)
        expect(flash[:error]).to eq("Passkey not found. Try using your email instead.")
      end
    end
  end

  describe "GET /login" do
    it "offers passkey sign in" do
      get login_path

      expect(response.body).to include("Sign in with a passkey")
      expect(response.body).to include("passkey-login-form")
    end
  end

  describe "GET /welcome" do
    it "offers passkey sign in" do
      allow_any_instance_of(ApplicationController).to receive(:current_identity).and_return(nil)
      allow_any_instance_of(ApplicationController).to receive(:identity_signed_in?).and_return(false)
      Rails.application.config.git_version = nil # skip the pre-existing footer bug

      get welcome_path

      expect(response.body).to include("Sign in with a passkey")
      expect(response.body).to include("passkey-login-form")
    end
  end
end
