require "rails_helper"

# The sharp edge of multi-account sessions: authentication assurance is per
# account. Signing into a second account must never inherit the first account's
# 2FA, step-up, or auth_time.
RSpec.describe "Authentication assurance isolation", type: :request do
  let(:mfa_identity) { enrol_totp(create(:identity, primary_email: "nora@hackclub.com")) }
  let(:single_factor_identity) { create(:identity, primary_email: "nora@example.com") }
  let(:program) { create(:program, scopes: "openid email") }

  before do
    Flipper.enable(BrowserAccountsController::FEATURE_FLAG)
    unless ENV["OIDC_SIGNING_KEY"].present?
      Doorkeeper::OpenidConnect.configuration
        .instance_variable_set(:@signing_key, OpenSSL::PKey::RSA.generate(2048).to_pem)
    end
  end

  after do
    Flipper.disable(BrowserAccountsController::FEATURE_FLAG)
    Current.reset_all
  end

  def authorize_and_exchange!(identity)
    BrowserSession.order(:created_at).last
      .remember_selection!(kind: "oidc", ref: program.uid, identity: identity)

    post "/oauth/authorize", params: {
      client_id: program.uid,
      redirect_uri: program.redirect_uri,
      response_type: "code",
      scope: "openid email",
      nonce: "test-nonce"
    }

    code = Rack::Utils.parse_query(URI.parse(response.headers["Location"]).query)["code"]

    post "/oauth/token", params: {
      grant_type: "authorization_code",
      code: code,
      redirect_uri: program.redirect_uri,
      client_id: program.uid,
      client_secret: program.secret
    }

    JWT.decode(JSON.parse(response.body)["id_token"], nil, false).first
  end

  describe "amr and acr" do
    it "does not lend one account's MFA to another" do
      mfa_session = sign_in_as(mfa_identity)
      single_session = add_account(single_factor_identity)

      expect(mfa_session.reload.amr_values).to include("mfa")
      expect(single_session.reload.amr_values).not_to include("mfa")

      claims = authorize_and_exchange!(single_factor_identity)

      expect(claims["sub"]).to eq(single_factor_identity.public_id)
      expect(claims["amr"]).not_to include("mfa")
      expect(claims["acr"]).to eq(IdentitySession::ACR_SINGLE_FACTOR)
      expect(claims["auth_time"]).to eq(single_session.reload.created_at.to_i)
    end

    it "reports the MFA account's own assurance when it is the one selected" do
      sign_in_as(single_factor_identity)
      mfa_session = add_account(mfa_identity)

      claims = authorize_and_exchange!(mfa_identity)

      expect(claims["sub"]).to eq(mfa_identity.public_id)
      expect(claims["amr"]).to include("mfa")
      expect(claims["acr"]).to eq(IdentitySession::ACR_MULTI_FACTOR)
      expect(claims["auth_time"]).to eq(mfa_session.reload.created_at.to_i)
    end

    it "uses the selected account's auth_time even when a sibling session is newer" do
      first = sign_in_as(single_factor_identity)
      add_account(mfa_identity)

      claims = authorize_and_exchange!(single_factor_identity)

      newest = IdentitySession.order(created_at: :desc).first
      expect(newest.identity_id).to eq(mfa_identity.id)
      expect(claims["auth_time"]).to eq(first.reload.created_at.to_i)
    end
  end

  describe "step-up" do
    it "does not carry across accounts" do
      mfa_session = sign_in_as(mfa_identity)
      other_session = add_account(single_factor_identity)

      mfa_session.record_step_up!(action: "oidc_reauth")

      expect(mfa_session.reload.recently_stepped_up?(for_action: "oidc_reauth")).to be true
      expect(other_session.reload.recently_stepped_up?(for_action: "oidc_reauth")).to be false
    end

    it "raises auth_time only for the account that stepped up" do
      first = sign_in_as(single_factor_identity)
      second = add_account(mfa_identity)

      second.record_step_up!(action: "oidc_reauth")

      claims = authorize_and_exchange!(single_factor_identity)
      expect(claims["auth_time"]).to eq(first.reload.created_at.to_i)
    end
  end

  describe "session lifetimes" do
    it "expires accounts independently" do
      first = sign_in_as(single_factor_identity)
      second = add_account(mfa_identity)

      first.update!(expires_at: 1.minute.ago)

      expect(second.reload).to be_live
      expect(BrowserSession.order(:created_at).last.live_identity_sessions).to contain_exactly(second)
    end

    it "does not extend an existing account's expiry when another is added" do
      first = sign_in_as(single_factor_identity)
      original = first.expires_at

      add_account(mfa_identity)

      expect(first.reload.expires_at).to be_within(2.seconds).of(original)
    end
  end

  describe "consent" do
    it "is never inherited from another account in the same browser" do
      sign_in_as(single_factor_identity)
      add_account(mfa_identity)

      # single_factor_identity consents...
      authorize_and_exchange!(single_factor_identity)
      expect(Doorkeeper::AccessGrant.where(resource_owner_id: single_factor_identity.id)).to exist

      # ...and the other account still has to be asked.
      BrowserSession.order(:created_at).last
        .remember_selection!(kind: "oidc", ref: program.uid, identity: mfa_identity)

      get "/oauth/authorize", params: {
        client_id: program.uid,
        redirect_uri: program.redirect_uri,
        response_type: "code",
        scope: "openid email",
        nonce: "test-nonce"
      }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(mfa_identity.primary_email)
    end
  end

  describe "grants" do
    it "stamps the selected account's session as the source" do
      sign_in_as(mfa_identity)
      single_session = add_account(single_factor_identity)

      authorize_and_exchange!(single_factor_identity)

      expect(Doorkeeper::AccessGrant.last.source_session_id).to eq(single_session.id)
    end
  end
end
