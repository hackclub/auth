# frozen_string_literal: true

# The JSON served at /api: a hand-holding entry point that points an agent at
# every machine-readable description of this service, plus a flat endpoint list
# so a client can see the public API surface in one request.
class APIIndex
  ENDPOINTS = [
    {
      method: "GET", path: "/api/v1/me",
      summary: "Get the authenticated user's identity, filtered to the token's scopes.",
      authentication: "access_token"
    },
    {
      method: "GET", path: "/api/v1/identities",
      summary: "List identities that authorized this program.",
      authentication: "program_key"
    },
    {
      method: "GET", path: "/api/v1/identities/{id}",
      summary: "Get one identity that authorized this program.",
      authentication: "program_key"
    },
    {
      method: "POST", path: "/api/v1/identities/{id}/set_slack_id",
      summary: "Attach a Slack ID to an identity (deprecated).",
      authentication: "program_key", scopes: [ "set_slack_id" ]
    },
    {
      method: "GET", path: "/api/external/check",
      summary: "Check a user's verification status by idv_id, email or slack_id.",
      authentication: "none"
    },
    {
      method: "GET", path: "/api/external/whoami",
      summary: "Report whether the calling browser has a Hack Club Auth session.",
      authentication: "none"
    },
    { method: "GET", path: "/api/v1/health_check", summary: "Service health.", authentication: "none" },
    { method: "GET", path: "/api/v1/hcb", summary: "Count of verifications awaiting review.", authentication: "none" },
    { method: "POST", path: "/oauth/token", summary: "Exchange an authorization code or refresh token for an access token.", authentication: "none" },
    { method: "POST", path: "/oauth/revoke", summary: "Revoke an access or refresh token.", authentication: "none" },
    { method: "GET", path: "/oauth/userinfo", summary: "OpenID Connect UserInfo.", authentication: "access_token", scopes: [ "openid" ] }
  ].freeze

  attr_reader :base_url

  def initialize(base_url:)
    @base_url = base_url.to_s.chomp("/")
  end

  def self.build(base_url:) = new(base_url:).as_json

  def as_json
    {
      name: "Hack Club Auth API",
      api_version: OpenapiDocument::API_VERSION,
      description: "Identity, verification status and OAuth 2.0 / OpenID Connect for Hack Club programs.",
      documentation_url: url("/docs/api"),
      openapi_url: url("/openapi.json"),
      openapi_yaml_url: url("/openapi.yaml"),
      oauth_authorization_server_url: url("/.well-known/oauth-authorization-server"),
      oauth_protected_resource_url: url("/.well-known/oauth-protected-resource"),
      openid_configuration_url: url("/.well-known/openid-configuration"),
      authorization_url: url("/oauth/authorize"),
      token_url: url("/oauth/token"),
      authentication: {
        access_token: "OAuth 2.0 bearer token for one user, obtained via the authorization code flow. Prefix: idntk.",
        program_key: "Machine-to-machine bearer credential for HQ-official programs. Prefix: prgmk.",
        none: "No credential required."
      },
      scopes: OAuthScope::ALL.map { |scope| { name: scope.name, description: scope.description } },
      endpoints: ENDPOINTS.map { |endpoint| endpoint.merge(url: url(endpoint[:path])) }
    }
  end

  private

  def url(path) = "#{base_url}#{path}"
end
