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
    { revoker: { adapter: "cloudflare_access", enabled: "1", fields: { account_id: "acct", api_token: "s3cr3t-token-value" }.merge(fields) } }
  end

  context "as a directory admin" do
    before { sign_in admin }

    it "creates a revoker and logs it on the app" do
      post developer_app_session_revoker_path(oauth_app), params: cf_params

      revoker = Directory::AppRevoker.find_by!(app_id: oauth_app.id)
      expect(revoker.settings).to eq("account_id" => "acct", "api_token" => "s3cr3t-token-value")
      expect(PublicActivity::Activity.where(trackable: oauth_app, key: "program.session_revoker_added")).to exist
    end

    it "never renders the secret back, and a blank secret keeps the stored one" do
      post developer_app_session_revoker_path(oauth_app), params: cf_params

      get developer_app_path(oauth_app)
      expect(response.body).not_to include("s3cr3t-token-value")
      expect(response.body).to include("acct")

      patch developer_app_session_revoker_path(oauth_app), params: cf_params(account_id: "acct2", api_token: "")
      expect(Directory::AppRevoker.find_by!(app_id: oauth_app.id).settings).to eq("account_id" => "acct2", "api_token" => "s3cr3t-token-value")
    end

    it "starts from scratch when switching adapter" do
      post developer_app_session_revoker_path(oauth_app), params: cf_params

      patch developer_app_session_revoker_path(oauth_app),
        params: { revoker: { adapter: "webhook", fields: { url: "https://app.example/revoke", api_token: "" } } }

      revoker = Directory::AppRevoker.find_by!(app_id: oauth_app.id)
      expect(revoker.adapter).to eq("webhook")
      expect(revoker.settings).to eq("url" => "https://app.example/revoke")
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
