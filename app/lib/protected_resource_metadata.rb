# frozen_string_literal: true

# RFC 9728 "OAuth 2.0 Protected Resource Metadata".
#
# Tells a client — without it having to read our docs — which authorization
# server protects this API and exactly which scopes it can ask for. Served at
# /.well-known/oauth-protected-resource by DiscoveryController.
class ProtectedResourceMetadata
  attr_reader :base_url, :resource_path

  # `resource_path` is the path RFC 9728 §3.1 inserted after the well-known
  # segment (e.g. "api/v1" for a resource identified as https://host/api/v1).
  def initialize(base_url:, resource_path: nil)
    @base_url = base_url.to_s.chomp("/")
    @resource_path = resource_path.to_s.delete_prefix("/").chomp("/").presence
  end

  def self.build(base_url:, resource_path: nil) = new(base_url:, resource_path:).as_json

  # RFC 9728 §3.3: `resource` MUST be identical to the resource identifier the
  # client requested metadata for, or a compliant client rejects the document.
  def resource = resource_path ? "#{base_url}/#{resource_path}" : base_url

  def as_json
    {
      resource: resource,
      authorization_servers: [ issuer ],
      jwks_uri: "#{base_url}/oauth/discovery/keys",
      scopes_supported: OAuthScope::ALL.map(&:name),
      bearer_methods_supported: [ "header" ],
      resource_name: "Hack Club Auth API",
      resource_documentation: "#{base_url}/docs/api",
      resource_policy_uri: "#{base_url}/docs/privacy",
      resource_tos_uri: "#{base_url}/docs/terms-of-service",
      # Not part of RFC 9728, but the cheapest way to hand a client the machine-
      # readable description and the per-scope descriptions it needs to pick a
      # least-privilege scope set.
      "openapi_url": "#{base_url}/openapi.json",
      "scope_descriptions": OAuthScope::ALL.to_h { |scope| [ scope.name, scope.description ] }
    }
  end

  # Mirrors Doorkeeper::OpenidConnect::DiscoveryController#issuer so the two
  # documents always name the same authorization server.
  def issuer
    configured = Doorkeeper::OpenidConnect.configuration.issuer
    value = if configured.respond_to?(:call)
      configured.arity == 1 ? configured.call(nil) : configured.call(nil, nil)
    else
      configured
    end
    value.to_s.presence || base_url
  rescue StandardError
    base_url
  end
end
