require "rails_helper"

RSpec.describe "API error responses", type: :request do
  let(:program) { create(:program, :with_all_scopes) }
  let(:identity) { create(:identity) }

  # Every error the API emits has to be parseable and self-describing: a stable
  # code to branch on, a message, a hint, and somewhere to read more.
  shared_examples "a structured JSON error" do |code:, status:|
    it "returns a #{status} JSON body with the #{code} code" do
      expect(response).to have_http_status(status)
      expect(response.media_type).to eq("application/json")

      body = JSON.parse(response.body)
      expect(body["error"]).to eq(code)
      expect(body["message"]).to be_present
      expect(body["hint"]).to be_present
      expect(body["status"]).to eq(Rack::Utils.status_code(status))
      expect(body["documentation_url"]).to eq("http://www.example.com/docs/api")
    end
  end

  describe "missing credentials" do
    before { get "/api/v1/me" }

    include_examples "a structured JSON error", code: "invalid_auth", status: :unauthorized

    it "challenges with a Bearer scheme pointing at the resource metadata" do
      challenge = response.headers["WWW-Authenticate"]

      expect(challenge).to start_with("Bearer ")
      expect(challenge).to include('realm="Hack Club Auth"')
      expect(challenge).to include('error="invalid_token"')
      expect(challenge).to include(
        'resource_metadata="http://www.example.com/.well-known/oauth-protected-resource"'
      )
    end
  end

  describe "revoked token" do
    let(:token) { create(:oauth_token, resource_owner: identity, application: program, scopes: "email") }

    before do
      token.update!(revoked_at: 1.hour.ago)
      get "/api/v1/me", headers: { "Authorization" => "Bearer #{token.token}" }
    end

    include_examples "a structured JSON error", code: "invalid_auth", status: :unauthorized
  end

  describe "a credential without permission for the endpoint" do
    let(:token) { create(:oauth_token, resource_owner: identity, application: program, scopes: "email") }

    before { get "/api/v1/identities", headers: { "Authorization" => "Bearer #{token.token}" } }

    include_examples "a structured JSON error", code: "not_authorized", status: :forbidden

    it "challenges with insufficient_scope so a client knows to re-authorize" do
      expect(response.headers["WWW-Authenticate"]).to include('error="insufficient_scope"')
    end
  end

  describe "a program key from a program that isn't HQ-official" do
    let(:community_program) { create(:program, trust_level: :community_trusted, scopes: "email") }

    before do
      get "/api/v1/identities", headers: { "Authorization" => "Bearer #{community_program.program_key}" }
    end

    include_examples "a structured JSON error", code: "not_authorized", status: :forbidden
  end

  describe "a missing record" do
    before do
      get "/api/v1/identities/ident!nope", headers: { "Authorization" => "Bearer #{program.program_key}" }
    end

    include_examples "a structured JSON error", code: "not_found", status: :not_found
  end

  describe "/api/v1/me with a program key (no user behind the credential)" do
    before { get "/api/v1/me", headers: { "Authorization" => "Bearer #{program.program_key}" } }

    include_examples "a structured JSON error", code: "not_found", status: :not_found
  end

  describe "a missing required parameter" do
    let(:slackless_identity) { create(:identity, slack_id: nil) }

    before do
      Doorkeeper::AccessGrant.create!(
        resource_owner: slackless_identity, application: program,
        token: SecureRandom.hex(32), expires_in: 600,
        redirect_uri: program.redirect_uri, scopes: "set_slack_id"
      )
      program.update!(scopes: "#{program.scopes} set_slack_id")

      post "/api/v1/identities/#{slackless_identity.public_id}/set_slack_id",
           headers: { "Authorization" => "Bearer #{program.program_key}" }
    end

    include_examples "a structured JSON error", code: "param_missing", status: :bad_request

    it "names the missing parameter in the message" do
      expect(JSON.parse(response.body)["message"]).to include("slack_id")
    end
  end

  describe "GET /api/external/check without an identifier" do
    before { get "/api/external/check" }

    include_examples "a structured JSON error", code: "param_missing", status: :bad_request

    it "names the accepted identifiers" do
      body = JSON.parse(response.body)

      expect(body["message"]).to include("idv_id", "email", "slack_id")
      expect(body["hint"]).to include("/api/external/check")
    end
  end

  describe "being rate limited" do
    # rack-attack throttles POST /oauth/token at 20/minute per IP.
    around do |example|
      cache = Rack::Attack.cache.store
      Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
      Rack::Attack.enabled = true
      example.run
    ensure
      Rack::Attack.cache.store = cache
    end

    it "answers an API client with a structured JSON 429" do
      21.times { post "/oauth/token", params: { grant_type: "authorization_code" } }

      expect(response).to have_http_status(:too_many_requests)
      expect(response.media_type).to eq("application/json")
      expect(response.headers["Retry-After"]).to eq("300")

      body = JSON.parse(response.body)
      expect(body["error"]).to eq("rate_limited")
      expect(body["message"]).to be_present
      expect(body["hint"]).to be_present
      expect(body["retry_after"]).to eq(300)
    end

    it "still yells at browsers in plain HTML" do
      # rack-attack throttles POST /login at 10/5min per IP.
      11.times do
        post "/login", params: { email: "nobody@example.com" }, headers: { "Accept" => "text/html" }
      end

      expect(response).to have_http_status(:too_many_requests)
      expect(response.media_type).to eq("text/html")
      expect(response.body).to eq("slow your roll!")
    end
  end

  describe "an unrouted path under /api" do
    before { get "/api/v1/definitely_not_an_endpoint" }

    include_examples "a structured JSON error", code: "not_found", status: :not_found

    it "points at the endpoint index and the OpenAPI description" do
      body = JSON.parse(response.body)

      expect(body["message"]).to include("GET /api/v1/definitely_not_an_endpoint")
      expect(body["hint"]).to include("http://www.example.com/api")
      expect(body["hint"]).to include("http://www.example.com/openapi.json")
    end
  end

  # Outside /api there is no catch-all route, so these 404s travel through
  # `config.exceptions_app` into ErrorsController. Dev and test normally show
  # the debug page instead, so borrow production's exception handling here.
  describe "an unrouted path outside /api" do
    around do |example|
      config = Rails.application.env_config
      original = config.values_at("action_dispatch.show_exceptions", "action_dispatch.show_detailed_exceptions")
      config["action_dispatch.show_exceptions"] = :all
      config["action_dispatch.show_detailed_exceptions"] = false
      example.run
    ensure
      config["action_dispatch.show_exceptions"], config["action_dispatch.show_detailed_exceptions"] = original
    end

    it "still renders the HTML error page for browsers" do
      get "/definitely-not-a-page", headers: { "Accept" => "text/html" }

      expect(response).to have_http_status(:not_found)
      expect(response.media_type).to eq("text/html")
      expect(response.body).not_to include('"error"')
    end

    it "renders JSON when the client asks for JSON" do
      get "/definitely-not-a-page", headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:not_found)
      expect(response.media_type).to eq("application/json")

      body = JSON.parse(response.body)
      expect(body["error"]).to eq("not_found")
      expect(body["message"]).to include("GET /definitely-not-a-page")
      expect(body["documentation_url"]).to eq("http://www.example.com/docs/api")
    end

    it "renders JSON for an unrouted OAuth path even without an Accept header" do
      get "/oauth/not-a-real-endpoint"

      expect(response).to have_http_status(:not_found)
      expect(response.media_type).to eq("application/json")
      expect(JSON.parse(response.body)["error"]).to eq("not_found")
    end
  end
end
