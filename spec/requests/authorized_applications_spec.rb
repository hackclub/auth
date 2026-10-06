require "rails_helper"

RSpec.describe "AuthorizedApplications", type: :request do
  let(:identity) { create(:identity) }
  let(:program) { create(:program, :with_all_scopes) }

  def tok(scopes:, app: program)
    create(:oauth_token, resource_owner: identity, application: app, scopes:)
  end

  before do
    allow_any_instance_of(ApplicationController).to receive(:current_identity).and_return(identity)
  end

  describe "GET /authorized_applications" do
    it "lists one entry per app even with multiple tokens" do
      tok(scopes: "basic_info")
      tok(scopes: "address phone")

      get authorized_applications_path
      expect(response).to have_http_status(:ok)
      expect(response.body.scan(program.name).size).to eq(1)
    end
  end

  describe "DELETE /authorized_applications/:id" do
    it "revokes all tokens for the app, not only the clicked one" do
      a = tok(scopes: "basic_info")
      b = tok(scopes: "address")
      other = tok(scopes: "email", app: create(:program))

      delete authorized_application_path(a)

      expect(response).to redirect_to(security_path)
      expect(a.reload.revoked_at).to be_present
      expect(b.reload.revoked_at).to be_present
      expect(other.reload.revoked_at).to be_nil
    end

    it "revokes access grants for the app" do
      t = tok(scopes: "basic_info")
      g = Doorkeeper::AccessGrant.create!(
        resource_owner: identity,
        application: program,
        token: SecureRandom.hex(32),
        expires_in: 600,
        redirect_uri: program.redirect_uri,
        scopes: "basic_info"
      )

      delete authorized_application_path(t)
      expect(g.reload.revoked_at).to be_present
    end

    it "rejects /api/v1/me for every former token of that app" do
      a = tok(scopes: "basic_info address")
      b = tok(scopes: "phone")

      delete authorized_application_path(a)

      get "/api/v1/me", headers: { "Authorization" => "Bearer #{a.token}" }
      expect(response).to have_http_status(:unauthorized)

      get "/api/v1/me", headers: { "Authorization" => "Bearer #{b.token}" }
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
