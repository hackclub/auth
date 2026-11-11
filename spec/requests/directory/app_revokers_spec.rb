# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Session revokers on the developer app page", type: :request do
  def sign_in(identity)
    allow_any_instance_of(ApplicationController).to receive(:current_identity).and_return(identity)
    allow_any_instance_of(ApplicationController).to receive(:identity_signed_in?).and_return(true)
  end

  let(:admin) do
    create(:identity).tap do |i|
      create(:backend_user, identity: i, directory_services_admin: true, program_manager: true)
      i.reload
    end
  end
  let(:owner) { create(:identity) }
  let(:oauth_app) { create(:program, owner_identity: owner, trust_level: :hq_official) }

  def cf_params(**fields)
    { revoker: { adapter: "cloudflare_access", enabled: "1", fields: { account_id: "0123456789abcdef0123456789abcdef", api_token: "s3cr3t-token-value" }.merge(fields) } }
  end

  context "as a directory admin" do
    before { sign_in admin }

    it "shows what changed in the app's activity log, without the secret" do
      post developer_app_session_revoker_path(oauth_app), params: cf_params
      patch developer_app_session_revoker_path(oauth_app),
        params: cf_params(account_id: "fedcba9876543210fedcba9876543210", api_token: "n3w-t0ken-value")

      get activity_log_developer_app_path(oauth_app)

      expect(response.body).to include("0123456789abcdef0123456789abcdef", "fedcba9876543210fedcba9876543210", "replaced")
      expect(response.body).not_to include("n3w-t0ken-value", "s3cr3t-token-value")
    end

    it "shows the app's owner that the account changed, but not the account ids" do
      post developer_app_session_revoker_path(oauth_app), params: cf_params
      patch developer_app_session_revoker_path(oauth_app),
        params: cf_params(account_id: "fedcba9876543210fedcba9876543210", api_token: "n3w-t0ken-value")

      sign_in owner
      get activity_log_developer_app_path(oauth_app)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("account_id")
      expect(response.body).not_to include("0123456789abcdef0123456789abcdef", "fedcba9876543210fedcba9876543210")
    end

    it "renders the page and lets the revoker be replaced when its config can't be read" do
      Directory::AppRevoker.create!(app: oauth_app, adapter: "webhook", config: { url: "https://a.example/r" }.to_json)
        .update_columns(config_ciphertext: "not-a-ciphertext")

      get developer_app_path(oauth_app)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("can&#39;t be read")

      patch developer_app_session_revoker_path(oauth_app),
        params: { revoker: { adapter: "webhook", enabled: "1", fields: { url: "https://b.example/r", secret: "s" } } }
      expect(Directory::AppRevoker.find_by!(app_id: oauth_app.id).settings).to eq("url" => "https://b.example/r", "secret" => "s")
    end

    it "creates a revoker and logs it on the app" do
      post developer_app_session_revoker_path(oauth_app), params: cf_params

      revoker = Directory::AppRevoker.find_by!(app_id: oauth_app.id)
      expect(revoker.settings).to eq("account_id" => "0123456789abcdef0123456789abcdef", "api_token" => "s3cr3t-token-value")
      expect(PublicActivity::Activity.where(trackable: oauth_app, key: "program.session_revoker_added")).to exist
    end

    it "never renders the secret back, and a blank secret keeps the stored one" do
      post developer_app_session_revoker_path(oauth_app), params: cf_params

      get developer_app_path(oauth_app)
      expect(response.body).not_to include("s3cr3t-token-value")
      expect(response.body).to include("0123456789abcdef0123456789abcdef")

      patch developer_app_session_revoker_path(oauth_app), params: cf_params(api_token: "")
      expect(Directory::AppRevoker.find_by!(app_id: oauth_app.id).settings).to eq("account_id" => "0123456789abcdef0123456789abcdef", "api_token" => "s3cr3t-token-value")
    end

    it "needs the api token re-entered when the account changes, and audits the change" do
      post developer_app_session_revoker_path(oauth_app), params: cf_params

      patch developer_app_session_revoker_path(oauth_app), params: cf_params(account_id: "fedcba9876543210fedcba9876543210", api_token: "")
      expect(flash[:alert]).to eq("re-enter the API token when changing the account")

      patch developer_app_session_revoker_path(oauth_app), params: cf_params(account_id: "fedcba9876543210fedcba9876543210", api_token: "new-token")
      changes = PublicActivity::Activity.where(trackable: oauth_app, key: "program.session_revoker_changed").last.parameters["changes"]
      expect(changes).to include("account_id" => [ "0123456789abcdef0123456789abcdef", "fedcba9876543210fedcba9876543210" ], "api_token" => "replaced")
      expect(changes.to_s).not_to include("new-token")
      expect(PaperTrail::Version.where(item_type: "Directory::AppRevoker").last.object_changes.to_s).not_to include("ciphertext")
    end

    it "refuses an account id that isn't cloudflare's hex id" do
      post developer_app_session_revoker_path(oauth_app), params: cf_params(account_id: "../../zones/x")
      expect(flash[:alert]).to include("32-character hex id")
      expect(Directory::AppRevoker.exists?(app_id: oauth_app.id)).to be(false)
    end

    it "refuses a webhook pointed at a private or local address" do
      %w[https://127.0.0.1/r https://10.1.2.3/r https://[::1]/r https://169.254.169.254/latest].each do |url|
        post developer_app_session_revoker_path(oauth_app),
          params: { revoker: { adapter: "webhook", enabled: "1", fields: { url: url } } }
        expect(Directory::AppRevoker.exists?(app_id: oauth_app.id)).to be(false), url
      end
    end

    it "starts from scratch when switching adapter" do
      post developer_app_session_revoker_path(oauth_app), params: cf_params

      patch developer_app_session_revoker_path(oauth_app),
        params: { revoker: { adapter: "webhook", fields: { url: "https://app.example/revoke", api_token: "" } } }

      revoker = Directory::AppRevoker.find_by!(app_id: oauth_app.id)
      expect(revoker.adapter).to eq("webhook")
      expect(revoker.settings).to eq("url" => "https://app.example/revoke")
    end

    it "won't carry a webhook secret over to a new url" do
      webhook = ->(url, secret) { { revoker: { adapter: "webhook", enabled: "1", fields: { url: url, secret: secret } } } }
      post developer_app_session_revoker_path(oauth_app), params: webhook.("https://a.example/r", "hook-secret")

      patch developer_app_session_revoker_path(oauth_app), params: webhook.("https://other.example/x", "")
      expect(flash[:alert]).to include("re-enter the secret")
      expect(Directory::AppRevoker.find_by!(app_id: oauth_app.id).settings)
        .to eq("url" => "https://a.example/r", "secret" => "hook-secret")

      patch developer_app_session_revoker_path(oauth_app), params: webhook.("https://a.example/r", "")
      expect(Directory::AppRevoker.find_by!(app_id: oauth_app.id).settings["secret"]).to eq("hook-secret")

      patch developer_app_session_revoker_path(oauth_app), params: webhook.("https://other.example/x", "new-secret")
      expect(Directory::AppRevoker.find_by!(app_id: oauth_app.id).settings)
        .to eq("url" => "https://other.example/x", "secret" => "new-secret")
    end

    it "refuses a missing required field or a non-https webhook" do
      post developer_app_session_revoker_path(oauth_app), params: cf_params(api_token: "")
      expect(Directory::AppRevoker.count).to eq(0)
      expect(flash[:alert]).to include("token is required")

      post developer_app_session_revoker_path(oauth_app),
        params: { revoker: { adapter: "webhook", fields: { url: "http://app.example/revoke" } } }
      expect(Directory::AppRevoker.count).to eq(0)
    end

    it "disables and removes it" do
      post developer_app_session_revoker_path(oauth_app), params: cf_params
      patch developer_app_session_revoker_path(oauth_app), params: cf_params(api_token: "").deep_merge(revoker: { enabled: "0" })
      expect(Directory::AppRevoker.find_by!(app_id: oauth_app.id).enabled).to be(false)

      delete developer_app_session_revoker_path(oauth_app)
      expect(Directory::AppRevoker.count).to eq(0)
    end

    it "shows confirm copy on requirement removal that warns when it's the last one" do
      ent = create(:directory_entitlement, slug: "only-one", name: "Only One")
      Directory::AppRequirement.create!(app: oauth_app, entitlement: ent)

      get developer_app_path(oauth_app)

      expect(response.body).to include(CGI.escapeHTML(I18n.t("directory.developer_apps.remove_last_requirement_confirm", name: "Only One")))
    end
  end

  context "as the app owner without directory admin" do
    before { sign_in owner }

    it "can't create one and doesn't see the section" do
      post developer_app_session_revoker_path(oauth_app), params: cf_params
      expect(Directory::AppRevoker.count).to eq(0)

      get developer_app_path(oauth_app)
      expect(response.body).not_to include(I18n.t("directory.developer_apps.revoker_heading"))
    end
  end
end
