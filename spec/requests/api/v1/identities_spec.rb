require "rails_helper"

RSpec.describe "API::V1::Identities", type: :request do
  let(:program) { create(:program, :with_all_scopes) }
  let(:identity) { create(:identity, :with_address) }

  describe "GET /api/v1/me" do
    context "with OAuth token" do
      let(:token) { create(:oauth_token, resource_owner: identity, application: program, scopes: "basic_info email") }

      it "returns identity data for authorized scopes only" do
        get "/api/v1/me", headers: { "Authorization" => "Bearer #{token.token}" }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        ident = json["identity"]

        # basic_info scope authorized
        expect(ident["first_name"]).to eq(identity.first_name)
        expect(ident["primary_email"]).to eq(identity.primary_email)

        # legal_name scope NOT authorized
        expect(ident).not_to have_key("legal_first_name")
        expect(ident).not_to have_key("legal_last_name")

        # address scope NOT authorized
        expect(ident).not_to have_key("addresses")
      end

      it "returns legal_name when that scope is authorized" do
        token.update!(scopes: "basic_info legal_name")

        get "/api/v1/me", headers: { "Authorization" => "Bearer #{token.token}" }

        json = JSON.parse(response.body)
        ident = json["identity"]

        expect(ident["legal_first_name"]).to eq(identity.legal_first_name)
        expect(ident["legal_last_name"]).to eq(identity.legal_last_name)
      end

      it "returns 401 for revoked token" do
        token.update!(revoked_at: 1.hour.ago)

        get "/api/v1/me", headers: { "Authorization" => "Bearer #{token.token}" }

        expect(response).to have_http_status(:unauthorized)
      end

      it "returns 401 for inactive program" do
        program.update!(active: false)

        get "/api/v1/me", headers: { "Authorization" => "Bearer #{token.token}" }

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with program key" do
      it "returns 404 (no current_identity when acting as program)" do
        get "/api/v1/me", headers: { "Authorization" => "Bearer #{program.program_key}" }

        expect(response).to have_http_status(:not_found)
      end
    end

    context "without authentication" do
      it "returns 401" do
        get "/api/v1/me"

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe "GET /api/v1/identities/:id" do
    context "with program key" do
      before do
        # Create access grant to add identity to program.identities
        Doorkeeper::AccessGrant.create!(
          resource_owner: identity,
          application: program,
          token: SecureRandom.hex(32),
          expires_in: 600,
          redirect_uri: program.redirect_uri,
          scopes: "basic_info email"
        )
        # Create access token for scope authorization check
        create(:oauth_token, resource_owner: identity, application: program, scopes: "basic_info email")
      end

      it "returns identity data for scopes the identity authorized" do
        get "/api/v1/identities/#{identity.public_id}",
            headers: { "Authorization" => "Bearer #{program.program_key}" }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        ident = json["identity"]

        # basic_info scope authorized by identity
        expect(ident["first_name"]).to eq(identity.first_name)
        expect(ident["primary_email"]).to eq(identity.primary_email)

        # legal_name scope NOT authorized by identity
        expect(ident).not_to have_key("legal_first_name")
      end

      it "respects per-identity scope authorization" do
        # Create second identity with different scopes
        identity2 = create(:identity)
        Doorkeeper::AccessGrant.create!(
          resource_owner: identity2,
          application: program,
          token: SecureRandom.hex(32),
          expires_in: 600,
          redirect_uri: program.redirect_uri,
          scopes: "legal_name"
        )
        create(:oauth_token, resource_owner: identity2, application: program, scopes: "legal_name")

        # Check first identity - has basic_info, not legal_name
        get "/api/v1/identities/#{identity.public_id}",
            headers: { "Authorization" => "Bearer #{program.program_key}" }

        json = JSON.parse(response.body)
        expect(json["identity"]["first_name"]).to eq(identity.first_name)
        expect(json["identity"]).not_to have_key("legal_first_name")

        # Check second identity - has legal_name, not basic_info
        get "/api/v1/identities/#{identity2.public_id}",
            headers: { "Authorization" => "Bearer #{program.program_key}" }

        json = JSON.parse(response.body)
        expect(json["identity"]).not_to have_key("first_name")
        expect(json["identity"]["legal_first_name"]).to eq(identity2.legal_first_name)
      end

      it "returns only id when identity has no matching scope authorizations" do
        # Create identity with access grant but no access tokens
        identity_no_auth = create(:identity)
        Doorkeeper::AccessGrant.create!(
          resource_owner: identity_no_auth,
          application: program,
          token: SecureRandom.hex(32),
          expires_in: 600,
          redirect_uri: program.redirect_uri,
          scopes: "basic_info"
        )
        # No access token created - identity never completed OAuth

        get "/api/v1/identities/#{identity_no_auth.public_id}",
            headers: { "Authorization" => "Bearer #{program.program_key}" }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        # Only id should be present, no PII
        expect(json["identity"].keys).to eq(["id"])
      end

      it "cannot access identity not associated with program" do
        unrelated_identity = create(:identity)

        get "/api/v1/identities/#{unrelated_identity.public_id}",
            headers: { "Authorization" => "Bearer #{program.program_key}" }

        expect(response).to have_http_status(:not_found)
      end
    end

    context "with OAuth token" do
      let(:token) { create(:oauth_token, resource_owner: identity, application: program, scopes: "basic_info") }

      it "returns 403 (only program keys can access show)" do
        get "/api/v1/identities/#{identity.public_id}",
            headers: { "Authorization" => "Bearer #{token.token}" }

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "GET /api/v1/identities" do
    context "with program key" do
      let!(:identity1) { create(:identity) }
      let!(:identity2) { create(:identity) }

      before do
        # identity1 authorized basic_info
        Doorkeeper::AccessGrant.create!(
          resource_owner: identity1,
          application: program,
          token: SecureRandom.hex(32),
          expires_in: 600,
          redirect_uri: program.redirect_uri,
          scopes: "basic_info"
        )
        create(:oauth_token, resource_owner: identity1, application: program, scopes: "basic_info")

        # identity2 authorized legal_name only
        Doorkeeper::AccessGrant.create!(
          resource_owner: identity2,
          application: program,
          token: SecureRandom.hex(32),
          expires_in: 600,
          redirect_uri: program.redirect_uri,
          scopes: "legal_name"
        )
        create(:oauth_token, resource_owner: identity2, application: program, scopes: "legal_name")
      end

      it "returns all program identities with per-identity scope filtering" do
        get "/api/v1/identities", headers: { "Authorization" => "Bearer #{program.program_key}" }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        identities = json["identities"]

        expect(identities.length).to eq(2)

        ident1 = identities.find { |i| i["id"] == identity1.public_id }
        ident2 = identities.find { |i| i["id"] == identity2.public_id }

        # identity1 has basic_info
        expect(ident1["first_name"]).to eq(identity1.first_name)
        expect(ident1).not_to have_key("legal_first_name")

        # identity2 has legal_name
        expect(ident2).not_to have_key("first_name")
        expect(ident2["legal_first_name"]).to eq(identity2.legal_first_name)
      end


    end

    context "with OAuth token" do
      let(:token) { create(:oauth_token, resource_owner: identity, application: program, scopes: "basic_info") }

      it "returns 403 (only program keys can access index)" do
        get "/api/v1/identities", headers: { "Authorization" => "Bearer #{token.token}" }

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "scope enforcement edge cases" do
    context "program requests scope it doesn't have configured" do
      let(:limited_program) { create(:program, scopes: "email") }

      before do
        Doorkeeper::AccessGrant.create!(
          resource_owner: identity,
          application: limited_program,
          token: SecureRandom.hex(32),
          expires_in: 600,
          redirect_uri: limited_program.redirect_uri,
          scopes: "email basic_info"
        )
        create(:oauth_token, resource_owner: identity, application: limited_program, scopes: "email basic_info")
      end

      it "only returns data for scopes the program has AND identity authorized" do
        get "/api/v1/identities/#{identity.public_id}",
            headers: { "Authorization" => "Bearer #{limited_program.program_key}" }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        ident = json["identity"]

        # email: program has it, identity authorized it
        expect(ident["primary_email"]).to eq(identity.primary_email)

        # basic_info: identity authorized but program doesn't have it
        expect(ident).not_to have_key("first_name")
      end
    end
  end
end
