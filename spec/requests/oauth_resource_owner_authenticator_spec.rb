# frozen_string_literal: true

require "rails_helper"

# Directory app requirements are enforced from Doorkeeper's resource_owner_authenticator
# (config/initializers/doorkeeper.rb), which runs on every Doorkeeper page that calls
# authenticate_resource_owner!, not only on the authorize endpoint.
RSpec.describe "OAuth resource owner authenticator", type: :request do
  let(:identity) { create(:identity) }
  let(:entitlement) { create(:directory_entitlement) }
  let(:program) { create(:program, redirect_uri: "https://app.example/callback\nhttps://app.example/other?keep=1") }

  before do
    allow_any_instance_of(ApplicationController).to receive(:current_identity).and_return(identity)
  end

  def require_entitlement!(app)
    Directory::AppRequirement.create!(app: app, entitlement: entitlement)
  end

  def authorize_params(app, **overrides)
    {
      client_id: app.uid,
      redirect_uri: app.redirect_uris.first,
      response_type: "code",
      scope: "basic_info",
      state: "st4te"
    }.merge(overrides)
  end

  def location_query
    Rack::Utils.parse_query(URI.parse(response.location).query)
  end

  describe "Doorkeeper pages without a client_id" do
    it "renders the authorized applications page" do
      create(:oauth_token, resource_owner: identity, application: program, scopes: "basic_info")

      get oauth_authorized_applications_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(program.name)
    end

    it "renders the native (oob) authorization code page" do
      get native_oauth_authorization_path(code: "c0de-for-oob")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("c0de-for-oob")
    end
  end

  describe "/oauth/authorize" do
    it "leaves an unknown client_id to Doorkeeper's invalid_client error" do
      get oauth_authorization_path, params: authorize_params(program, client_id: "no-such-client")

      expect(response).to have_http_status(:unauthorized)
      expect(response.body).to include(I18n.t("doorkeeper.errors.messages.invalid_client"))
    end

    it "shows the consent screen for an app without requirements" do
      get oauth_authorization_path, params: authorize_params(program)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Continue to #{program.name}?")
    end

    context "when the identity lacks the app's required entitlement" do
      before { require_entitlement!(program) }

      it "redirects to the requested registered URI with access_denied and state" do
        get oauth_authorization_path, params: authorize_params(program)

        expect(response).to have_http_status(:found)
        expect(response.location).to start_with("https://app.example/callback?")
        expect(location_query).to include("error" => "access_denied", "state" => "st4te")
      end

      it "keeps the registered URI's own query params" do
        get oauth_authorization_path, params: authorize_params(program, redirect_uri: "https://app.example/other?keep=1")

        expect(response.location).to start_with("https://app.example/other?")
        expect(location_query).to include("keep" => "1", "error" => "access_denied", "state" => "st4te")
      end

      it "falls back to the first registered URI rather than an unregistered one" do
        get oauth_authorization_path, params: authorize_params(program, redirect_uri: "https://evil.example/callback")

        expect(response.location).to start_with("https://app.example/callback?")
        expect(location_query).to include("error" => "access_denied", "state" => "st4te")
      end

      it "shows the requirement-denied page when the registered URI is oob" do
        oob_app = create(:program, redirect_uri: "urn:ietf:wg:oauth:2.0:oob")
        require_entitlement!(oob_app)

        get oauth_authorization_path, params: authorize_params(oob_app)

        expect(response).to redirect_to(directory_requirement_denied_path)
        follow_redirect!
        expect(response).to have_http_status(:ok)
      end

      it "denies a direct POST approval without issuing a grant" do
        expect {
          post oauth_authorization_path, params: authorize_params(program)
        }.not_to change(Doorkeeper::AccessGrant, :count)

        expect(response.location).to start_with("https://app.example/callback?")
        expect(location_query).to include("error" => "access_denied", "state" => "st4te")
      end
    end

    context "when the identity is an effective member of the required entitlement" do
      before do
        require_entitlement!(program)
        person = create(:directory_person, identity: identity)
        Directory.mutate!(cause: "test") do
          Directory::Membership.create!(collection: entitlement, member_person: person, created_by_identity_id: identity.id)
        end
      end

      it "passes through to the consent screen" do
        get oauth_authorization_path, params: authorize_params(program)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Continue to #{program.name}?")
      end

      it "issues a code on approval" do
        expect {
          post oauth_authorization_path, params: authorize_params(program)
        }.to change(Doorkeeper::AccessGrant, :count).by(1)

        expect(response.location).to start_with("https://app.example/callback?")
        expect(location_query).to include("code", "state" => "st4te")
      end
    end
  end
end
