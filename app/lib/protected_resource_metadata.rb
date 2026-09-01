# frozen_string_literal: true

# RFC 9728 "OAuth 2.0 Protected Resource Metadata".
#
# Tells a client — without it having to read our docs — which authorization
# server protects this API and exactly which scopes it can ask for. Served at
# /.well-known/oauth-protected-resource by WellKnownController.
class ProtectedResourceMetadata
  attr_reader :base_url

  def initialize(base_url:)
    @base_url = base_url.to_s.chomp("/")
  end

  def self.build(base_url:) = new(base_url:).as_json

  def as_json
    {
      resource: base_url,
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
