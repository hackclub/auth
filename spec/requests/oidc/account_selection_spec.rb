require "rails_helper"

RSpec.describe "OIDC account selection", type: :request do
  let(:work) { create(:identity, primary_email: "nora@hackclub.com") }
  let(:personal) { create(:identity, primary_email: "nora@example.com") }
  let(:program) { create(:program, scopes: "openid email") }

  before do
    Flipper.enable(BrowserAccountsController::FEATURE_FLAG)
    ensure_signing_key!
  end

  after do
    Flipper.disable(BrowserAccountsController::FEATURE_FLAG)
    Current.reset_all
  end

  def ensure_signing_key!
    return if ENV["OIDC_SIGNING_KEY"].present?

    Doorkeeper::OpenidConnect.configuration
      .instance_variable_set(:@signing_key, OpenSSL::PKey::RSA.generate(2048).to_pem)
  end

  def authorize_params(extra = {})
    {
      client_id: program.uid,
      redirect_uri: program.redirect_uri,
      response_type: "code",
      scope: "openid email",
      nonce: "test-nonce"
    }.merge(extra)
  end

  def authorize!(extra = {})
    get "/oauth/authorize", params: authorize_params(extra)
  end

  def approve!(extra = {})
    post "/oauth/authorize", params: authorize_params(extra)
  end

  def id_token_for(identity)
    token = create(:oauth_token, resource_owner: identity, application: program, scopes: "openid email")
    Doorkeeper::OpenidConnect::IdToken.new(token, "nonce").as_jws_token
  end

  def error_from_redirect
    Rack::Utils.parse_query(URI.parse(response.headers["Location"]).query)["error"]
  end

  describe "with one account" do
    before { sign_in_as(work) }

    it "goes straight to the consent screen with no prompt" do
      authorize!

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(work.primary_email)
    end

    it "renders the chooser for prompt=select_account instead of erroring" do
      authorize!(prompt: "select_account")

      expect(response).to redirect_to(%r{/accounts})
    end

    it "succeeds silently for prompt=none" do
      approve!(prompt: "none")

      expect(response.headers["Location"]).to include(program.redirect_uri)
      expect(error_from_redirect).to be_nil
    end
  end

  describe "with two accounts" do
    before do
      sign_in_as(work)
      add_account(personal)
    end

    it "asks which account to use" do
      authorize!

      expect(response).to redirect_to(%r{/accounts\?.*pending=})
    end

    it "parks the request so it can be resumed intact" do
      authorize!(state: "xyz")

      pending = PendingAuthorization.order(:created_at).last
      expect(pending.kind).to eq("oidc")
      expect(pending.payload.dig("params", "state")).to eq("xyz")
      expect(pending.payload.dig("params", "nonce")).to eq("test-nonce")
    end

    it "resumes the original request after a choice, exactly once" do
      authorize!(state: "xyz")
      pending_token = PendingAuthorization.order(:created_at).last.token

      post switch_browser_account_path, params: { id: work.public_id, pending: pending_token }
      expect(response).to redirect_to(resume_browser_account_path(pending: pending_token))

      follow_redirect!
      expect(response.headers["Location"]).to include("/oauth/authorize")
      expect(response.headers["Location"]).to include("state=xyz")

      # Replay is refused.
      get resume_browser_account_path(pending: pending_token)
      expect(response).to redirect_to(root_path)
    end

    it "refuses a handle parked by a different browser session" do
      other_pending = create(:pending_authorization)

      get resume_browser_account_path(pending: other_pending.token)

      expect(response).to redirect_to(root_path)
      expect(other_pending.reload.consumed_at).to be_nil
    end

    describe "prompt=none" do
      it "returns account_selection_required on the redirect URI, preserving state" do
        authorize!(prompt: "none", state: "keep-me")

        expect(response.headers["Location"]).to start_with(program.redirect_uri)
        expect(error_from_redirect).to eq("account_selection_required")
        expect(response.headers["Location"]).to include("state=keep-me")
      end

      it "resolves via a sticky selection" do
        # prompt=none also requires prior consent, so grant it first — otherwise
        # the (correct) consent_required masks whether selection worked.
        create(:oauth_token, resource_owner: work, application: program, scopes: "openid email")
        BrowserSession.order(:created_at).last
          .remember_selection!(kind: "oidc", ref: program.uid, identity: work)

        authorize!(prompt: "none")

        expect(error_from_redirect).to be_nil
        expect(Doorkeeper::AccessGrant.last.resource_owner_id).to eq(work.id)
      end

      it "resolves via login_hint" do
        create(:oauth_token, resource_owner: personal, application: program, scopes: "openid email")

        authorize!(prompt: "none", login_hint: personal.primary_email)

        expect(error_from_redirect).to be_nil
        expect(Doorkeeper::AccessGrant.last.resource_owner_id).to eq(personal.id)
      end
    end

    describe "login_hint" do
      it "selects the matching account without asking" do
        authorize!(login_hint: work.primary_email)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(work.primary_email)
      end

      it "asks when it matches no signed-in account" do
        authorize!(login_hint: "nobody@example.com")

        expect(response).to redirect_to(%r{/accounts})
      end
    end

    describe "id_token_hint" do
      it "constrains selection to the named subject" do
        authorize!(id_token_hint: id_token_for(work))

        expect(error_from_redirect).to be_nil
        expect(Doorkeeper::AccessGrant.last.resource_owner_id).to eq(work.id)
      end

      it "asks when the subject isn't signed in here" do
        stranger = create(:identity, primary_email: "stranger@example.com")

        authorize!(id_token_hint: id_token_for(stranger))

        expect(response).to redirect_to(%r{/accounts})
      end

      it "rejects an unverifiable token" do
        authorize!(id_token_hint: "not.a.jwt")

        expect(error_from_redirect).to eq("invalid_request")
      end
    end

    describe "the consent screen" do
      it "shows the selected account, not the active one" do
        BrowserSession.order(:created_at).last
          .remember_selection!(kind: "oidc", ref: program.uid, identity: work)

        authorize!

        expect(response.body).to include(work.primary_email)
        expect(response.body).not_to include(personal.primary_email)
      end

      it "carries the hints through the round-trip" do
        BrowserSession.order(:created_at).last
          .remember_selection!(kind: "oidc", ref: program.uid, identity: work)

        authorize!(max_age: "3600", login_hint: work.primary_email)

        expect(response.body).to include('name="max_age"')
        expect(response.body).to include('name="login_hint"')
        expect(response.body).to include('name="selected_account"')
        # prompt must not round-trip, or select_account/consent would loop.
        expect(response.body).not_to include('name="prompt"')
      end

      it "refuses to approve for an account other than the one displayed" do
        BrowserSession.order(:created_at).last
          .remember_selection!(kind: "oidc", ref: program.uid, identity: work)

        approve!(selected_account: personal.public_id)

        expect(response).to redirect_to(%r{/accounts})
        expect(Doorkeeper::AccessGrant.count).to eq(0)
      end
    end
  end

  describe "discovery" do
    it "advertises prompt and acr support" do
      get "/.well-known/openid-configuration"

      body = JSON.parse(response.body)
      expect(body["prompt_values_supported"]).to include("select_account", "none", "login")
      expect(body["acr_values_supported"]).to include(IdentitySession::ACR_MULTI_FACTOR)
      expect(body["claims_supported"]).to include("amr", "acr", "auth_time")
    end
  end
end
