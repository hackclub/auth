# frozen_string_literal: true

# Serves every machine-readable description of this service:
#
#   GET /openapi.json                            OpenAPI 3.1 (also /api/openapi.json)
#   GET /openapi.yaml                            same document as YAML (also /api/openapi.yaml)
#   GET /api                                     API entry point / endpoint index
#   GET /.well-known/oauth-protected-resource    RFC 9728 protected resource metadata
#   GET /.well-known/api-catalog                 RFC 9727 API catalog linkset
#
# These are public by design and CORS-open so browser and agent clients can read
# them directly. RFC 8414 authorization server metadata and the OpenID Connect
# discovery document are served by doorkeeper-openid_connect.
class DiscoveryController < ActionController::API
  CACHE_FOR = 1.hour

  before_action :set_discovery_headers, except: :not_found

  def openapi
    document = OpenapiDocument.build(base_url: base_url)

    respond_with_document(document)
  end

  def api_index
    render json: APIIndex.build(base_url: base_url)
  end

  def oauth_protected_resource
    render json: ProtectedResourceMetadata.build(base_url: base_url, resource_path: params[:resource_path])
  end

  # RFC 9727: a linkset (RFC 9264) pointing at the descriptions of this API.
  def api_catalog
    catalog = {
      linkset: [
        {
          anchor: base_url,
          "service-desc": [
            { href: url_for_path("/openapi.json"), type: "application/vnd.oai.openapi+json", title: "OpenAPI 3.1 description (JSON)" },
            { href: url_for_path("/openapi.yaml"), type: "application/vnd.oai.openapi+yaml", title: "OpenAPI 3.1 description (YAML)" }
          ],
          "service-doc": [
            { href: url_for_path("/docs/api"), type: "text/html", title: "Hack Club Auth API documentation" }
          ],
          "service-meta": [
            { href: url_for_path("/.well-known/oauth-protected-resource"), type: "application/json", title: "OAuth 2.0 protected resource metadata (RFC 9728)" },
            { href: url_for_path("/.well-known/oauth-authorization-server"), type: "application/json", title: "OAuth 2.0 authorization server metadata (RFC 8414)" },
            { href: url_for_path("/.well-known/openid-configuration"), type: "application/json", title: "OpenID Connect discovery" }
          ],
          "status-page": [
            { href: url_for_path("/api/v1/health_check"), type: "application/json", title: "Health check" }
          ]
        }
      ]
    }

    render json: catalog, content_type: "application/linkset+json"
  end

  def preflight = head :ok

  # Catch-all for unmatched /api/* paths, so a client that guesses a path gets a
  # parseable answer pointing at the real endpoint list.
  def not_found
    body = APIErrors.body(
      :not_found,
      base_url: base_url,
      message: "No endpoint matches #{request.request_method} #{request.path}.",
      hint: "The available endpoints are listed at #{url_for_path('/api')} and described at #{url_for_path('/openapi.json')}."
    )

    render json: body, status: :not_found
  end

  private

  def respond_with_document(document)
    if request.format.to_s.include?("yaml") || request.path.end_with?(".yaml")
      render plain: document.deep_stringify_keys.to_yaml,
             content_type: "application/yaml"
    else
      render json: document
    end
  end

  def base_url = request.base_url

  def url_for_path(path) = "#{base_url}#{path}"

  def set_discovery_headers
    response.set_header("Access-Control-Allow-Origin", "*")
    response.set_header("Access-Control-Allow-Methods", "GET, OPTIONS")
    response.set_header("Access-Control-Allow-Headers", "Content-Type")
    expires_in CACHE_FOR, public: true
  end
end
