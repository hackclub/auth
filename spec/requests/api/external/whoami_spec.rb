require "rails_helper"

RSpec.describe "API::External::Identities#whoami", type: :request do
  let(:origin) { "https://program.hackclub.com" }
  let(:identity) { create(:identity, first_name: "Heidi", primary_email: "heidi@hackclub.com") }

  # Stub the session cookie lookup (SessionsHelper) to isolate whoami behaviour.
  def signed_in_as(ident)
    allow_any_instance_of(API::External::IdentitiesController)
      .to receive(:current_identity).and_return(ident)
  end

  context "enabled app, matching Origin" do
    let!(:program) do
      create(:program, whoami_enabled: true, whoami_allowed_origin: origin)
    end

    it "returns identity for a signed-in visitor with credentialed CORS headers" do
      signed_in_as(identity)

      get "/api/external/whoami", headers: { "Origin" => origin }

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json).to eq(
        "signed_in" => true,
        "email" => "heidi@hackclub.com",
        "first_name" => "Heidi"
      )
      expect(response.headers["Access-Control-Allow-Origin"]).to eq(origin)
      expect(response.headers["Access-Control-Allow-Credentials"]).to eq("true")
      expect(response.headers["Vary"]).to include("Origin")
    end

    it "returns an inert signed-out body (still CORS-readable) when not signed in" do
      signed_in_as(nil)

      get "/api/external/whoami", headers: { "Origin" => origin }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq(
        "signed_in" => false, "email" => nil, "first_name" => nil
      )
      expect(response.headers["Access-Control-Allow-Origin"]).to eq(origin)
    end

    it "matches Origin case-insensitively" do
      signed_in_as(identity)

      get "/api/external/whoami", headers: { "Origin" => origin.upcase }

      expect(JSON.parse(response.body)["signed_in"]).to be(true)
    end

    it "sets CORS headers on the OPTIONS preflight" do
      options "/api/external/whoami", headers: { "Origin" => origin }

      expect(response).to have_http_status(:ok)
      expect(response.headers["Access-Control-Allow-Origin"]).to eq(origin)
      expect(response.headers["Access-Control-Allow-Methods"]).to include("GET")
    end
  end

  context "app exists but feature disabled" do
    let!(:program) do
      create(:program, whoami_enabled: false, whoami_allowed_origin: origin)
    end

    it "never leaks identity and sends no CORS allow-origin header" do
      signed_in_as(identity)

      get "/api/external/whoami", headers: { "Origin" => origin }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq(
        "signed_in" => false, "email" => nil, "first_name" => nil
      )
      expect(response.headers["Access-Control-Allow-Origin"]).to be_nil
    end
  end

  context "Origin not on any allowlist" do
    let!(:program) do
      create(:program, whoami_enabled: true, whoami_allowed_origin: origin)
    end

    it "returns inert body with no CORS allow-origin header" do
      signed_in_as(identity)

      get "/api/external/whoami", headers: { "Origin" => "https://evil.example.com" }

      expect(JSON.parse(response.body)).to eq(
        "signed_in" => false, "email" => nil, "first_name" => nil
      )
      expect(response.headers["Access-Control-Allow-Origin"]).to be_nil
    end
  end

  context "no Origin header" do
    let!(:program) do
      create(:program, whoami_enabled: true, whoami_allowed_origin: origin)
    end

    it "returns inert body" do
      signed_in_as(identity)

      get "/api/external/whoami"

      expect(JSON.parse(response.body)).to eq(
        "signed_in" => false, "email" => nil, "first_name" => nil
      )
      expect(response.headers["Access-Control-Allow-Origin"]).to be_nil
    end
  end
end
