require "rails_helper"

RSpec.describe "API discovery documents", type: :request do
  describe "GET /openapi.json" do
    before { get "/openapi.json" }

    it "serves a JSON OpenAPI 3.1 document" do
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")

      doc = JSON.parse(response.body)
      expect(doc["openapi"]).to start_with("3.1")
      expect(doc["info"]["title"]).to eq("Hack Club Auth API")
      expect(doc["info"]["version"]).to eq(OpenapiDocument::API_VERSION)
      expect(doc["servers"].first["url"]).to eq("http://www.example.com")
    end

    it "describes the public and authenticated endpoints" do
      paths = JSON.parse(response.body)["paths"]

      expect(paths.keys).to include(
        "/api/v1/me",
        "/api/v1/identities",
        "/api/v1/identities/{id}",
        "/api/external/check",
        "/api/external/whoami",
        "/api/v1/health_check",
        "/oauth/token"
      )
    end

    it "is readable cross-origin and cacheable" do
      expect(response.headers["Access-Control-Allow-Origin"]).to eq("*")
      expect(response.headers["Cache-Control"]).to include("public")
    end

    it "resolves every internal $ref" do
      doc = JSON.parse(response.body)

      refs = []
      walk = lambda do |node|
        case node
        when Hash
          node.each { |key, value| key == "$ref" ? refs << value : walk.call(value) }
        when Array
          node.each { |value| walk.call(value) }
        end
      end
      walk.call(doc)

      expect(refs).not_to be_empty
      refs.uniq.each do |ref|
        pointer = ref.delete_prefix("#/").split("/")
        expect(doc.dig(*pointer)).to be_present, "dangling $ref: #{ref}"
      end
    end
  end

  describe "the OpenAPI document's internal consistency" do
    subject(:doc) do
      get "/openapi.json"
      JSON.parse(response.body)
    end

    it "gives every operation a unique operationId, a summary and responses" do
      operations = doc["paths"].flat_map { |path, methods| methods.map { |verb, op| [ "#{verb.upcase} #{path}", op ] } }

      expect(operations).not_to be_empty
      operations.each do |label, operation|
        expect(operation["operationId"]).to be_present, "#{label} has no operationId"
        expect(operation["summary"]).to be_present, "#{label} has no summary"
        expect(operation["responses"]).to be_present, "#{label} has no responses"
      end

      ids = operations.map { |_label, operation| operation["operationId"] }
      expect(ids.uniq.length).to eq(ids.length), "duplicate operationIds: #{ids.tally.select { |_, n| n > 1 }.keys}"
    end

    # OpenAPI 3.1: only oauth2 / openIdConnect schemes may list scopes. A non-empty
    # list on an http-bearer scheme makes the document fail strict validation.
    it "lists scopes only for schemes that can carry them" do
      schemes = doc.dig("components", "securitySchemes")

      doc["paths"].each do |path, methods|
        methods.each do |verb, operation|
          operation["security"].to_a.each do |requirement|
            requirement.each do |scheme_name, scopes|
              type = schemes.dig(scheme_name, "type")
              next if %w[oauth2 openIdConnect].include?(type)

              expect(scopes).to be_empty,
                "#{verb.upcase} #{path} lists scopes for #{scheme_name} (type: #{type})"
            end
          end
        end
      end
    end

    it "only names security schemes it declares" do
      declared = doc.dig("components", "securitySchemes").keys

      referenced = doc["paths"].values.flat_map(&:values)
        .flat_map { |operation| operation["security"].to_a }
        .flat_map(&:keys)

      expect(referenced.uniq - declared).to be_empty
    end

    it "only requires scopes the authorization server actually supports" do
      required_scopes = doc["paths"].values.flat_map(&:values)
        .flat_map { |operation| operation["security"].to_a }
        .flat_map(&:values).flatten

      expect(required_scopes.uniq - OAuthScope::ALL.map(&:name)).to be_empty
    end

    it "annotates identity fields only with scopes the server supports" do
      annotated = doc.dig("components", "schemas", "Identity", "properties")
        .values.flat_map { |property| property["x-scopes"].to_a }

      expect(annotated).not_to be_empty
      expect(annotated.uniq - OAuthScope::ALL.map(&:name)).to be_empty
    end

    it "roots every path at /" do
      expect(doc["paths"].keys).to all(start_with("/"))
    end
  end

  describe "GET /openapi.yaml" do
    it "serves the same document as YAML" do
      get "/openapi.yaml"

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/yaml")

      doc = YAML.safe_load(response.body)
      expect(doc["openapi"]).to start_with("3.1")
      expect(doc["paths"]).to include("/api/v1/me")
    end
  end

  describe "the mirrored /api/openapi.* paths" do
    it "serves JSON" do
      get "/api/openapi.json"

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["openapi"]).to start_with("3.1")
    end

    it "serves YAML" do
      get "/api/openapi.yaml"

      expect(response).to have_http_status(:ok)
      expect(YAML.safe_load(response.body)["openapi"]).to start_with("3.1")
    end
  end

  describe "declared scopes" do
    it "declares every OAuth scope in the oauth2 security scheme" do
      get "/openapi.json"

      scopes = JSON.parse(response.body)
        .dig("components", "securitySchemes", "oauth2", "flows", "authorizationCode", "scopes")

      expect(scopes.keys).to match_array(OAuthScope::ALL.map(&:name))
      OAuthScope::ALL.each do |scope|
        expect(scopes[scope.name]).to eq(scope.description)
      end
    end

    it "points the oauth2 flow at the real authorization and token endpoints" do
      get "/openapi.json"

      flow = JSON.parse(response.body)
        .dig("components", "securitySchemes", "oauth2", "flows", "authorizationCode")

      expect(flow["authorizationUrl"]).to eq("http://www.example.com/oauth/authorize")
      expect(flow["tokenUrl"]).to eq("http://www.example.com/oauth/token")
    end

    it "annotates identity fields with the scopes that expose them" do
      get "/openapi.json"

      properties = JSON.parse(response.body).dig("components", "schemas", "Identity", "properties")

      expect(properties.dig("primary_email", "x-scopes")).to contain_exactly("email", "basic_info")
      expect(properties.dig("legal_first_name", "x-scopes")).to eq([ "legal_name" ])
      expect(properties["id"]).not_to have_key("x-scopes")
    end
  end

  describe "GET /.well-known/oauth-protected-resource" do
    before { get "/.well-known/oauth-protected-resource" }

    it "returns RFC 9728 protected resource metadata" do
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")

      metadata = JSON.parse(response.body)
      expect(metadata["resource"]).to eq("http://www.example.com")
      expect(metadata["authorization_servers"]).to be_present
      expect(metadata["bearer_methods_supported"]).to eq([ "header" ])
      expect(metadata["resource_documentation"]).to eq("http://www.example.com/docs/api")
    end

    it "lists every supported scope" do
      expect(JSON.parse(response.body)["scopes_supported"]).to match_array(OAuthScope::ALL.map(&:name))
    end

    it "includes a description for each scope so a client can pick least privilege" do
      descriptions = JSON.parse(response.body)["scope_descriptions"]

      expect(descriptions.keys).to match_array(OAuthScope::ALL.map(&:name))
      expect(descriptions["email"]).to eq("See your email address")
    end

    it "is readable cross-origin" do
      expect(response.headers["Access-Control-Allow-Origin"]).to eq("*")
    end
  end

  describe "GET /.well-known/oauth-protected-resource/:resource_path" do
    it "answers for a path-scoped resource identifier" do
      get "/.well-known/oauth-protected-resource/api/v1"

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["scopes_supported"]).to match_array(OAuthScope::ALL.map(&:name))
    end

    # RFC 9728 §3.3: `resource` must be identical to the identifier the client
    # asked about, or a compliant client rejects the document as a mismatch.
    it "echoes the requested resource identifier back in `resource`" do
      get "/.well-known/oauth-protected-resource/api/v1"

      expect(JSON.parse(response.body)["resource"]).to eq("http://www.example.com/api/v1")
    end
  end

  describe "GET /.well-known/oauth-authorization-server" do
    it "advertises every supported scope (RFC 8414)" do
      get "/.well-known/oauth-authorization-server"

      expect(response).to have_http_status(:ok)
      metadata = JSON.parse(response.body)

      expect(metadata["scopes_supported"]).to match_array(OAuthScope::ALL.map(&:name))
      expect(metadata["authorization_endpoint"]).to be_present
      expect(metadata["token_endpoint"]).to be_present
    end
  end

  describe "GET /.well-known/api-catalog" do
    it "returns an RFC 9727 linkset pointing at the API descriptions" do
      get "/.well-known/api-catalog"

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/linkset+json")

      links = JSON.parse(response.body).dig("linkset", 0)
      expect(links["anchor"]).to eq("http://www.example.com")
      expect(links["service-desc"].map { |l| l["href"] })
        .to include("http://www.example.com/openapi.json")
      expect(links["service-meta"].map { |l| l["href"] })
        .to include("http://www.example.com/.well-known/oauth-protected-resource")
    end
  end

  describe "GET /api" do
    before { get "/api" }

    it "returns a machine-readable entry point" do
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")

      index = JSON.parse(response.body)
      expect(index["name"]).to eq("Hack Club Auth API")
      expect(index["openapi_url"]).to eq("http://www.example.com/openapi.json")
      expect(index["oauth_protected_resource_url"])
        .to eq("http://www.example.com/.well-known/oauth-protected-resource")
    end

    it "lists the endpoints with their authentication requirements" do
      endpoints = JSON.parse(response.body)["endpoints"]

      me = endpoints.find { |e| e["path"] == "/api/v1/me" }
      expect(me["authentication"]).to eq("access_token")
      expect(me["url"]).to eq("http://www.example.com/api/v1/me")

      check = endpoints.find { |e| e["path"] == "/api/external/check" }
      expect(check["authentication"]).to eq("none")
    end

    it "lists every scope with its description" do
      scopes = JSON.parse(response.body)["scopes"]

      expect(scopes.map { |s| s["name"] }).to match_array(OAuthScope::ALL.map(&:name))
    end

    it "documents every endpoint it lists in the OpenAPI description" do
      listed = JSON.parse(response.body)["endpoints"]

      get "/openapi.json"
      paths = JSON.parse(response.body)["paths"]

      listed.each do |endpoint|
        expect(paths[endpoint["path"]]).to be_present, "#{endpoint['path']} is missing from the OpenAPI paths"
        expect(paths[endpoint["path"]].keys).to include(endpoint["method"].downcase)
      end
    end
  end

  describe "CORS preflight" do
    it "answers OPTIONS on the discovery endpoints" do
      %w[/openapi /api /.well-known/oauth-protected-resource /.well-known/api-catalog].each do |path|
        process :options, path

        expect(response).to have_http_status(:ok), "OPTIONS #{path} failed"
        expect(response.headers["Access-Control-Allow-Origin"]).to eq("*")
      end
    end
  end
end
