# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Directory app pages", type: :request do
  def sign_in(identity)
    allow_any_instance_of(ApplicationController).to receive(:current_identity).and_return(identity)
    allow_any_instance_of(ApplicationController).to receive(:identity_signed_in?).and_return(true)
  end

  # a directory admin with no other backend role: can't open the developer app page
  let(:admin) do
    create(:identity).tap do |i|
      create(:backend_user, identity: i, directory_services_admin: true)
      i.reload
    end
  end
  let!(:oauth_app) { create(:program, :with_groups, name: "Gated Thing", owner_identity: create(:identity)) }
  let(:entitlement) { create(:directory_entitlement, slug: "staff") }
  let(:page) { directory_app_path(oauth_app) }

  context "as a directory admin" do
    before { sign_in admin }

    it "lists official apps and shows one without its credentials" do
      get directory_apps_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Gated Thing")

      get page
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(oauth_app.secret)
      expect(response.body).not_to include(oauth_app.uid)
    end

    it "wires, unwires, requires and unrequires from this page and comes back to it" do
      post directory_exposures_path, params: { app_id: oauth_app.id, entitlement_slug: entitlement.slug, claim_name: "staff", return_to: page }
      expect(response).to redirect_to(page)
      exposure = Directory::Exposure.find_by!(app: oauth_app)

      delete directory_exposure_path(exposure), params: { return_to: page }
      expect(response).to redirect_to(page)
      expect(Directory::Exposure.exists?(exposure.id)).to be(false)

      post directory_app_requirements_path, params: { app_id: oauth_app.id, entitlement_slug: entitlement.slug, return_to: page }
      expect(response).to redirect_to(page)
      delete directory_app_requirement_path(entitlement.slug), params: { app_id: oauth_app.id, return_to: page }
      expect(response).to redirect_to(page)
      expect(Directory::AppRequirement.where(app: oauth_app)).not_to exist
    end

    it "sets up and removes a session revoker from this page" do
      post developer_app_session_revoker_path(oauth_app),
        params: { return_to: page, revoker: { adapter: "cloudflare_access", enabled: "1", fields: { account_id: "0123456789abcdef0123456789abcdef", api_token: "tok-s3cret" } } }
      expect(response).to redirect_to(page)
      expect(Directory::AppRevoker.find_by!(app_id: oauth_app.id).settings["api_token"]).to eq("tok-s3cret")

      get page
      expect(response.body).not_to include("tok-s3cret")

      delete developer_app_session_revoker_path(oauth_app), params: { return_to: page }
      expect(response).to redirect_to(page)
      expect(Directory::AppRevoker.where(app_id: oauth_app.id)).not_to exist
    end

    it "ignores a return_to that isn't one of the app's own pages" do
      post directory_exposures_path, params: { app_id: oauth_app.id, entitlement_slug: entitlement.slug, claim_name: "staff", return_to: "https://evil.example/" }
      expect(response).to redirect_to(developer_app_path(oauth_app))
    end
  end

  context "as anyone else" do
    it "answers 404" do
      person = create(:directory_person)
      sign_in person.identity

      get directory_apps_path
      expect(response).to have_http_status(:not_found)
      get page
      expect(response).to have_http_status(:not_found)
    end
  end

  it "marks exposures on an app without the groups scope as not sent, and doesn't count them" do
    sign_in admin
    inert = create(:program, name: "No Groups App", trust_level: :hq_official, owner_identity: create(:identity))
    exposure = Directory::Exposure.new(app: inert, entitlement: entitlement, claim_name: "staff")
    exposure.save!(validate: false)

    get directory_app_path(inert)
    expect(response.body).to include(CGI.escapeHTML(I18n.t("directory.developer_apps.exposure_not_sent")))

    get directory_apps_path
    row = response.parsed_body.css("tr").find { |tr| tr.text.include?("No Groups App") }
    expect(row.css("td").map { |td| td.text.strip }).to include("0")
  end
end
