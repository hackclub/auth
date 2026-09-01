# frozen_string_literal: true

# Builds the OpenAPI 3.1 description of the public Hack Club Auth API.
#
# The scope list is derived from OAuthScope::ALL so the machine-readable
# description can never drift from what the authorization server actually
# grants. Served (as JSON and YAML) by OpenapiController.
class OpenapiDocument
  # Bump when the shape of the described API changes in a breaking way.
  API_VERSION = "1.0.0"

  # Scopes that gate identity fields. `set_slack_id` is a write scope and
  # `openid`/`profile` are OIDC-only, so they're excluded from field docs.
  FIELD_SCOPES = %w[email name slack_id phone birthdate verification_status address legal_name basic_info].freeze

  VERIFICATION_STATUSES = %w[needs_submission pending verified ineligible].freeze

  CHECK_RESULTS = %w[needs_submission pending verified_eligible verified_but_over_18 rejected not_found unknown].freeze

  attr_reader :base_url

  def initialize(base_url:)
    @base_url = base_url.to_s.chomp("/")
  end

  def self.build(base_url:) = new(base_url:).as_json

  # The set of scopes the authorization server understands, as a
  # { name => description } map suitable for an OpenAPI oauth2 flow.
  def self.scopes
    OAuthScope::ALL.to_h { |scope| [ scope.name, scope.description ] }
  end

  def self.scope_names = OAuthScope::ALL.map(&:name)

  def as_json
    {
      openapi: "3.1.0",
      info: info,
      servers: [ { url: base_url, description: "Hack Club Auth" } ],
      externalDocs: {
        description: "Hack Club Auth developer documentation",
        url: "#{base_url}/docs/api"
      },
      security: [ { oauth2: [] } ],
      tags: tags,
      paths: paths,
      components: components
    }
  end

  private

  def info
    {
      title: "Hack Club Auth API",
      summary: "Identity, verification status and OAuth 2.0 / OpenID Connect for Hack Club programs.",
      description: <<~MD,
        Hack Club Auth is the identity provider behind Hack Club programs. It issues OAuth 2.0
        access tokens and OpenID Connect ID tokens, and exposes a small REST API for reading the
        identity data a user has consented to share.

        ## Authentication

        Most endpoints take a bearer token in the `Authorization` header:

        ```
        Authorization: Bearer idntk.mraowj2z72e1x8i2a60o88j3h7d0f1
        ```

        Two kinds of bearer credential exist:

        - **User access tokens** (`idntk.` prefix) are obtained through the OAuth 2.0
          authorization code flow and act on behalf of a single signed-in user.
        - **Program keys** (`prgmk.` prefix) are machine-to-machine credentials issued only to
          HQ-official programs. They act on behalf of the program across every identity that has
          authorized it.

        ## Scopes

        Every identity field is gated by a scope. A response only contains the fields covered by
        the intersection of (a) the scopes the program is configured for and (b) the scopes the
        user actually granted. Fields with no value are omitted entirely rather than returned as
        `null`, so treat every property as optional.

        Scope metadata is also published as RFC 9728 protected resource metadata at
        `/.well-known/oauth-protected-resource` and as RFC 8414 authorization server metadata at
        `/.well-known/oauth-authorization-server`.

        ## Errors

        Every error from this API is a JSON object with a stable machine-readable `error` code, a
        human-readable `message`, a `hint` describing how to resolve it, and a `documentation_url`.
      MD
      version: API_VERSION,
      termsOfService: "#{base_url}/docs/terms-of-service",
      contact: {
        name: "Hack Club Auth",
        url: "#{base_url}/docs/contact",
        email: "auth@hackclub.com"
      },
      license: { name: "AGPL-3.0-or-later", identifier: "AGPL-3.0-or-later" }
    }
  end

  def tags
    [
      { name: "Identity", description: "Read identity data a user has consented to share." },
      { name: "Verification", description: "Publicly readable verification / eligibility checks." },
      { name: "OAuth", description: "Token issuance, revocation and introspection." },
      { name: "Discovery", description: "Machine-readable descriptions of this API." },
      { name: "Status", description: "Service health." }
    ]
  end

  def paths
    {
      "/api/v1/me" => { get: me_operation },
      "/api/v1/identities" => { get: list_identities_operation },
      "/api/v1/identities/{id}" => { get: show_identity_operation },
      "/api/v1/identities/{id}/set_slack_id" => { post: set_slack_id_operation },
      "/api/external/check" => { get: check_operation },
      "/api/external/whoami" => { get: whoami_operation },
      "/api/v1/health_check" => { get: health_check_operation },
      "/api/v1/hcb" => { get: hcb_operation },
      "/oauth/token" => { post: token_operation },
      "/oauth/revoke" => { post: revoke_operation },
      "/oauth/userinfo" => { get: userinfo_operation },
      "/api" => { get: api_index_operation },
      "/openapi.json" => { get: openapi_operation },
      "/.well-known/oauth-protected-resource" => { get: protected_resource_operation },
      "/.well-known/oauth-authorization-server" => { get: authorization_server_operation },
      "/.well-known/openid-configuration" => { get: openid_configuration_operation }
    }
  end

  # -- operations ------------------------------------------------------------

  def me_operation
    {
      operationId: "getCurrentIdentity",
      summary: "Get the authenticated user's identity",
      description: <<~MD,
        Returns the identity behind the access token, limited to the scopes that token carries,
        plus the list of granted scopes so a client can tell what it is allowed to ask for.

        Requires a user access token. Program keys have no user attached and receive `404`.
      MD
      tags: [ "Identity" ],
      security: [ { oauth2: [] } ],
      responses: {
        "200" => json_response("The authenticated identity.", ref("MeResponse")),
        "401" => error_response("invalid_auth"),
        "404" => error_response("not_found")
      }
    }
  end

  def list_identities_operation
    {
      operationId: "listIdentities",
      summary: "List identities that authorized this program",
      description: <<~MD,
        Paginated list of every identity that has completed an OAuth authorization with the
        calling program. Each identity is filtered by the scopes *that identity* granted, so
        different entries in one response may expose different fields.

        Requires a program key.
      MD
      tags: [ "Identity" ],
      security: [ { programKey: [] } ],
      parameters: [
        {
          name: "page", in: "query", required: false,
          description: "1-indexed page number.",
          schema: { type: "integer", minimum: 1, default: 1 }
        },
        {
          name: "per_page", in: "query", required: false,
          description: "Identities per page. Values outside 1..100 are clamped.",
          schema: { type: "integer", minimum: 1, maximum: 100, default: 100 }
        }
      ],
      responses: {
        "200" => json_response("A page of identities.", ref("IdentityListResponse")),
        "401" => error_response("invalid_auth"),
        "403" => error_response("not_authorized")
      }
    }
  end

  def show_identity_operation
    {
      operationId: "getIdentity",
      summary: "Get one identity by public ID",
      description: <<~MD,
        Returns a single identity that has authorized the calling program, filtered by the scopes
        that identity granted. Identities that have not authorized the program are indistinguishable
        from identities that do not exist — both return `404`.

        Requires a program key.
      MD
      tags: [ "Identity" ],
      security: [ { programKey: [] } ],
      parameters: [ identity_id_parameter ],
      responses: {
        "200" => json_response("The requested identity.", ref("IdentityResponse")),
        "401" => error_response("invalid_auth"),
        "403" => error_response("not_authorized"),
        "404" => error_response("not_found")
      }
    }
  end

  def set_slack_id_operation
    {
      operationId: "setIdentitySlackId",
      summary: "Attach a Slack ID to an identity",
      description: <<~MD,
        Associates a Slack member ID with an identity that has no Slack ID yet. If one is already
        set the call is a no-op and returns `{ "message": "slack already associated?" }`.

        Requires a program key carrying the `set_slack_id` scope. This endpoint is deprecated.
      MD
      tags: [ "Identity" ],
      deprecated: true,
      security: [ { programKey: [ "set_slack_id" ] } ],
      parameters: [ identity_id_parameter ],
      requestBody: {
        required: true,
        content: {
          "application/json" => {
            schema: {
              type: "object",
              required: [ "slack_id" ],
              properties: {
                slack_id: { type: "string", description: "Slack member ID.", examples: [ "U06QK6AG3RD" ] }
              }
            }
          }
        }
      },
      responses: {
        "200" => {
          description: "The updated identity, or a no-op message if a Slack ID was already set.",
          content: {
            "application/json" => {
              schema: { anyOf: [ ref("IdentityResponse"), ref("MessageResponse") ] }
            }
          }
        },
        "400" => error_response("param_missing"),
        "401" => error_response("invalid_auth"),
        "403" => error_response("not_authorized"),
        "404" => error_response("not_found")
      }
    }
  end

  def check_operation
    {
      operationId: "checkVerification",
      summary: "Check a user's verification status",
      description: <<~MD,
        Public, unauthenticated eligibility check. Provide exactly one of `idv_id`, `email` or
        `slack_id`. Intended for program integrations; CORS is open to any origin.

        This endpoint is public by design. Reaching it is not a security vulnerability.
      MD
      tags: [ "Verification" ],
      security: [ {} ],
      parameters: [
        {
          name: "idv_id", in: "query", required: false,
          description: "The user's Hack Club Auth public ID.",
          schema: { type: "string" }, examples: { id: { value: "ident!abc123" } }
        },
        {
          name: "email", in: "query", required: false,
          description: "The user's primary email address.",
          schema: { type: "string", format: "email" },
          examples: { email: { value: "orpheus@hackclub.com" } }
        },
        {
          name: "slack_id", in: "query", required: false,
          description: "The user's Slack member ID.",
          schema: { type: "string" }, examples: { slack: { value: "U06QK6AG3RD" } }
        }
      ],
      responses: {
        "200" => json_response("The verification result.", ref("CheckResponse")),
        "400" => error_response("param_missing")
      }
    }
  end

  def whoami_operation
    {
      operationId: "whoami",
      summary: "Identify the browser's signed-in user",
      description: <<~MD,
        Browser-only endpoint. Reads the Hack Club Auth session cookie and reports whether the
        visitor is signed in. It answers with identity data only when the request's `Origin` matches
        an origin an allowlisted program registered, and must be called with credentials included.

        Bearer tokens do nothing here — this is not a substitute for `/api/v1/me`.
      MD
      tags: [ "Identity" ],
      security: [ {} ],
      parameters: [
        {
          name: "Origin", in: "header", required: false,
          description: "Browser-set origin. Must match a registered whoami origin for identity data to be returned.",
          schema: { type: "string" }
        }
      ],
      responses: {
        "200" => json_response("Sign-in state for the calling browser.", ref("WhoamiResponse"))
      }
    }
  end

  def health_check_operation
    {
      operationId: "healthCheck",
      summary: "Service health",
      description: "Unauthenticated liveness probe that also exercises the database.",
      tags: [ "Status" ],
      security: [ {} ],
      responses: {
        "200" => json_response("The service is healthy.", ref("MessageResponse"))
      }
    }
  end

  def hcb_operation
    {
      operationId: "getPendingVerificationCount",
      summary: "Count of verifications awaiting review",
      description: "Unauthenticated operational counter used by Hack Club dashboards.",
      tags: [ "Status" ],
      security: [ {} ],
      responses: {
        "200" => json_response("Pending verification count.", ref("PendingCountResponse"))
      }
    }
  end

  def token_operation
    {
      operationId: "createToken",
      summary: "Exchange an authorization code or refresh token for an access token",
      description: "Standard OAuth 2.0 token endpoint (RFC 6749). Supports the `authorization_code` and `refresh_token` grants.",
      tags: [ "OAuth" ],
      security: [ {} ],
      requestBody: {
        required: true,
        content: {
          "application/x-www-form-urlencoded" => { schema: ref("TokenRequest") },
          "application/json" => { schema: ref("TokenRequest") }
        }
      },
      responses: {
        "200" => json_response("A newly issued access token.", ref("TokenResponse")),
        "400" => json_response("The grant was rejected.", ref("OAuthError")),
        "401" => json_response("Client authentication failed.", ref("OAuthError")),
        "429" => error_response("rate_limited")
      }
    }
  end

  def revoke_operation
    {
      operationId: "revokeToken",
      summary: "Revoke an access or refresh token",
      description: "Standard OAuth 2.0 token revocation endpoint (RFC 7009). Always responds `200` so clients cannot probe token validity.",
      tags: [ "OAuth" ],
      security: [ {} ],
      requestBody: {
        required: true,
        content: {
          "application/x-www-form-urlencoded" => {
            schema: {
              type: "object",
              required: [ "token" ],
              properties: {
                token: { type: "string", description: "The access or refresh token to revoke." },
                token_type_hint: { type: "string", enum: [ "access_token", "refresh_token" ] },
                client_id: { type: "string" },
                client_secret: { type: "string" }
              }
            }
          }
        }
      },
      responses: {
        "200" => { description: "The token is revoked, or was never valid." },
        "401" => json_response("Client authentication failed.", ref("OAuthError"))
      }
    }
  end

  def userinfo_operation
    {
      operationId: "getUserinfo",
      summary: "OpenID Connect UserInfo",
      description: "Returns OIDC claims for the access token's subject. Requires the `openid` scope; the claims returned depend on the other granted scopes.",
      tags: [ "OAuth" ],
      security: [ { oauth2: [ "openid" ] } ],
      responses: {
        "200" => json_response("OIDC claims for the token's subject.", ref("UserinfoResponse")),
        "401" => json_response("The token is missing, expired or revoked.", ref("OAuthError"))
      }
    }
  end

  def api_index_operation
    {
      operationId: "getApiIndex",
      summary: "API entry point",
      description: "Machine-readable index of the public API: version, endpoint list, scopes and links to this description.",
      tags: [ "Discovery" ],
      security: [ {} ],
      responses: {
        "200" => json_response("The API index.", ref("ApiIndexResponse")),
        "429" => error_response("rate_limited")
      }
    }
  end

  def openapi_operation
    {
      operationId: "getOpenapiDocument",
      summary: "This OpenAPI description",
      description: "Also served as YAML at `/openapi.yaml` and mirrored at `/api/openapi.json` and `/api/openapi.yaml`.",
      tags: [ "Discovery" ],
      security: [ {} ],
      responses: {
        "200" => {
          description: "The OpenAPI 3.1 description of this API.",
          content: {
            "application/json" => { schema: { type: "object" } },
            "application/vnd.oai.openapi+json" => { schema: { type: "object" } }
          }
        },
        "429" => error_response("rate_limited")
      }
    }
  end

  def protected_resource_operation
    {
      operationId: "getProtectedResourceMetadata",
      summary: "OAuth 2.0 protected resource metadata (RFC 9728)",
      description: "Declares the resource identifier, its authorization server and every scope this resource understands.",
      tags: [ "Discovery" ],
      security: [ {} ],
      responses: {
        "200" => json_response("Protected resource metadata.", ref("ProtectedResourceMetadata")),
        "429" => error_response("rate_limited")
      }
    }
  end

  def authorization_server_operation
    {
      operationId: "getAuthorizationServerMetadata",
      summary: "OAuth 2.0 authorization server metadata (RFC 8414)",
      description: "Endpoint locations, supported grants and `scopes_supported` for the authorization server.",
      tags: [ "Discovery" ],
      security: [ {} ],
      responses: {
        "200" => json_response("Authorization server metadata.", { type: "object" }),
        "429" => error_response("rate_limited")
      }
    }
  end

  def openid_configuration_operation
    {
      operationId: "getOpenidConfiguration",
      summary: "OpenID Connect discovery document",
      description: "OpenID Provider configuration, including the JWKS location at `/oauth/discovery/keys`.",
      tags: [ "Discovery" ],
      security: [ {} ],
      responses: {
        "200" => json_response("OpenID Provider metadata.", { type: "object" }),
        "429" => error_response("rate_limited")
      }
    }
  end

  def identity_id_parameter
    {
      name: "id", in: "path", required: true,
      description: "The identity's public ID.",
      schema: { type: "string" },
      examples: { id: { value: "ident!abc123" } }
    }
  end

  # -- components ------------------------------------------------------------

  def components
    {
      securitySchemes: security_schemes,
      schemas: schemas,
      responses: reusable_responses
    }
  end

  def security_schemes
    {
      oauth2: {
        type: "oauth2",
        description: <<~MD,
          Authorization code flow. Request the narrowest set of scopes your integration needs —
          users see each one on the consent screen, and programs are only permitted the scopes
          their trust level allows.
        MD
        flows: {
          authorizationCode: {
            authorizationUrl: "#{base_url}/oauth/authorize",
            tokenUrl: "#{base_url}/oauth/token",
            refreshUrl: "#{base_url}/oauth/token",
            scopes: self.class.scopes
          }
        }
      },
      programKey: {
        type: "http",
        scheme: "bearer",
        bearerFormat: "prgmk.<secret>",
        description: <<~MD
          Machine-to-machine credential issued only to HQ-official programs, passed as
          `Authorization: Bearer prgmk.…`. A program key can read every identity that authorized
          the program, so prefer a user access token whenever one will do.
        MD
      }
    }
  end

  def schemas
    {
      Identity: identity_schema,
      Address: address_schema,
      IdentityResponse: {
        type: "object",
        required: [ "identity" ],
        properties: { identity: ref("Identity") }
      },
      MeResponse: {
        type: "object",
        required: [ "identity", "scopes" ],
        properties: {
          identity: ref("Identity"),
          scopes: {
            type: "array",
            description: "Scopes carried by the access token used for this request.",
            items: { type: "string", enum: self.class.scope_names }
          }
        }
      },
      IdentityListResponse: {
        type: "object",
        required: [ "identities" ],
        properties: { identities: { type: "array", items: ref("Identity") } }
      },
      CheckResponse: {
        type: "object",
        required: [ "result", "note" ],
        properties: {
          result: {
            type: "string",
            enum: CHECK_RESULTS,
            description: <<~MD
              - `needs_submission` — the user has not started verification
              - `pending` — verification is under review
              - `verified_eligible` — verified and eligible for YSWS programs
              - `verified_but_over_18` — verified, but not YSWS eligible
              - `rejected` — verification was rejected
              - `not_found` — no identity matched the identifier
            MD
          },
          note: { type: "string", description: "Static note explaining that this endpoint is intentionally public." },
          your_fortune_is: { type: "string", description: "Occasionally present. Not part of the contract." }
        }
      },
      WhoamiResponse: {
        type: "object",
        required: [ "signed_in", "email", "first_name" ],
        properties: {
          signed_in: { type: "boolean" },
          email: { type: [ "string", "null" ], format: "email" },
          first_name: { type: [ "string", "null" ] }
        }
      },
      MessageResponse: {
        type: "object",
        required: [ "message" ],
        properties: { message: { type: "string" } }
      },
      PendingCountResponse: {
        type: "object",
        required: [ "pending" ],
        properties: { pending: { type: "integer", description: "Verifications currently awaiting review." } }
      },
      TokenRequest: {
        type: "object",
        required: [ "grant_type" ],
        properties: {
          grant_type: { type: "string", enum: [ "authorization_code", "refresh_token" ] },
          code: { type: "string", description: "Required for `authorization_code`." },
          refresh_token: { type: "string", description: "Required for `refresh_token`." },
          redirect_uri: { type: "string", format: "uri" },
          client_id: { type: "string" },
          client_secret: { type: "string" },
          code_verifier: { type: "string", description: "PKCE verifier, when the authorization request used PKCE." }
        }
      },
      TokenResponse: {
        type: "object",
        required: [ "access_token", "token_type" ],
        properties: {
          access_token: { type: "string" },
          token_type: { type: "string", examples: [ "Bearer" ] },
          expires_in: { type: "integer", description: "Lifetime in seconds." },
          refresh_token: { type: "string" },
          scope: { type: "string", description: "Space-separated granted scopes." },
          id_token: { type: "string", description: "Present when the `openid` scope was granted." },
          created_at: { type: "integer", description: "Unix timestamp." }
        }
      },
      UserinfoResponse: {
        type: "object",
        description: "OIDC claims. Which claims appear depends on the granted scopes.",
        required: [ "sub" ],
        properties: {
          sub: { type: "string", description: "The identity's public ID." },
          email: { type: "string", format: "email" },
          email_verified: { type: "boolean" },
          name: { type: "string" },
          given_name: { type: "string" },
          family_name: { type: "string" },
          nickname: { type: "string" },
          updated_at: { type: "integer" },
          phone_number: { type: "string" },
          phone_number_verified: { type: "boolean" },
          birthdate: { type: "string", format: "date" },
          address: { type: "object", description: "OIDC address claim." },
          slack_id: { type: "string" },
          verification_status: { type: "string", enum: VERIFICATION_STATUSES },
          ysws_eligible: { type: "boolean" }
        }
      },
      ProtectedResourceMetadata: {
        type: "object",
        required: [ "resource", "authorization_servers", "scopes_supported" ],
        properties: {
          resource: { type: "string", format: "uri" },
          authorization_servers: { type: "array", items: { type: "string", format: "uri" } },
          scopes_supported: { type: "array", items: { type: "string", enum: self.class.scope_names } },
          bearer_methods_supported: { type: "array", items: { type: "string" } },
          resource_documentation: { type: "string", format: "uri" }
        }
      },
      ApiIndexResponse: {
        type: "object",
        required: [ "name", "api_version", "documentation_url", "openapi_url", "endpoints" ],
        properties: {
          name: { type: "string" },
          api_version: { type: "string" },
          description: { type: "string" },
          documentation_url: { type: "string", format: "uri" },
          openapi_url: { type: "string", format: "uri" },
          openapi_yaml_url: { type: "string", format: "uri" },
          oauth_authorization_server_url: { type: "string", format: "uri" },
          oauth_protected_resource_url: { type: "string", format: "uri" },
          openid_configuration_url: { type: "string", format: "uri" },
          scopes: {
            type: "array",
            items: {
              type: "object",
              required: [ "name", "description" ],
              properties: { name: { type: "string" }, description: { type: "string" } }
            }
          },
          endpoints: {
            type: "array",
            items: {
              type: "object",
              required: [ "method", "path", "url", "summary", "authentication" ],
              properties: {
                method: { type: "string" },
                path: { type: "string" },
                url: { type: "string", format: "uri" },
                summary: { type: "string" },
                authentication: { type: "string", enum: [ "none", "access_token", "program_key" ] },
                scopes: { type: "array", items: { type: "string" } }
              }
            }
          }
        }
      },
      Error: error_schema,
      OAuthError: {
        type: "object",
        description: "RFC 6749 error response from the OAuth endpoints.",
        required: [ "error" ],
        properties: {
          error: { type: "string", examples: [ "invalid_grant" ] },
          error_description: { type: "string" },
          state: { type: "string" }
        }
      }
    }
  end

  def identity_schema
    {
      type: "object",
      description: <<~MD,
        A Hack Club Auth identity. Only `id` is guaranteed: every other property appears solely
        when the caller holds the scope that gates it *and* the value is present. Blank values are
        omitted rather than returned as `null`.
      MD
      required: [ "id" ],
      properties: {
        id: scoped(nil, { type: "string", description: "Stable public identifier.", examples: [ "ident!abc123" ] }),
        first_name: scoped(%w[name basic_info], { type: "string" }),
        last_name: scoped(%w[name basic_info], { type: "string" }),
        primary_email: scoped(%w[email basic_info], { type: "string", format: "email" }),
        slack_id: scoped(%w[slack_id basic_info], { type: "string", description: "Slack member ID." }),
        phone_number: scoped(%w[phone basic_info], { type: "string" }),
        birthday: scoped(%w[birthdate basic_info], { type: "string", format: "date" }),
        legal_first_name: scoped(%w[legal_name], { type: "string" }),
        legal_last_name: scoped(%w[legal_name], { type: "string" }),
        verification_status: scoped(%w[verification_status basic_info], {
          type: "string", enum: VERIFICATION_STATUSES
        }),
        ysws_eligible: scoped(%w[verification_status basic_info], {
          type: "boolean", description: "Whether the identity qualifies for You Ship, We Ship programs."
        }),
        fatal_rejection: scoped(%w[verification_status basic_info], {
          type: "boolean",
          description: "Present and `true` only when `verification_status` is `ineligible` and the rejection cannot be appealed."
        }),
        verification_status_reason: scoped(%w[basic_info], { type: "string" }),
        rejection_reason: scoped(%w[basic_info], { type: "string", description: "Alias of `verification_status_reason`." }),
        rejection_reason_details: scoped(%w[basic_info], { type: "string" }),
        addresses: scoped(%w[address], { type: "array", items: ref("Address") })
      }
    }
  end

  def address_schema
    {
      type: "object",
      description: "A mailing address. Blank fields are omitted.",
      required: [ "id" ],
      properties: {
        id: { type: "string" },
        first_name: { type: "string" },
        last_name: { type: "string" },
        line_1: { type: "string" },
        line_2: { type: "string" },
        city: { type: "string" },
        state: { type: "string" },
        postal_code: { type: "string" },
        country: { type: "string", description: "ISO 3166-1 alpha-2 country code." },
        phone_number: { type: "string" },
        primary: { type: "boolean", description: "Whether this is the identity's primary address." }
      }
    }
  end

  def error_schema
    {
      type: "object",
      description: "Every non-OAuth error from this API uses this shape.",
      required: [ "error", "message", "status", "documentation_url" ],
      properties: {
        error: {
          type: "string",
          description: "Stable machine-readable error code. Branch on this, not on `message`.",
          enum: APIErrors::CATALOG.keys.map(&:to_s)
        },
        message: { type: "string", description: "Human-readable description of what went wrong." },
        hint: { type: "string", description: "How to resolve the error." },
        status: { type: "integer", description: "HTTP status code, repeated for clients that only read the body." },
        documentation_url: { type: "string", format: "uri" }
      }
    }
  end

  def reusable_responses
    referenced = referenced_error_codes

    APIErrors::CATALOG.select { |code, _| referenced.include?(code) }.to_h do |code, definition|
      [
        code.to_s.camelize,
        {
          description: definition[:message],
          content: {
            "application/json" => {
              schema: ref("Error"),
              example: APIErrors.body(code, base_url: base_url)
            }
          }
        }
      ]
    end
  end

  # Walks the built paths for `#/components/responses/...` references, so the
  # emitted component set is exactly what's used.
  def referenced_error_codes
    refs = []
    walk = lambda do |node|
      case node
      when Hash then node.each { |key, value| key == :"$ref" ? refs << value : walk.call(value) }
      when Array then node.each { |value| walk.call(value) }
      end
    end
    walk.call(paths)

    refs.filter_map { |ref| ref[%r{\A#/components/responses/(.+)\z}, 1]&.underscore&.to_sym }.uniq
  end

  # -- helpers ---------------------------------------------------------------

  def ref(name) = { "$ref": "#/components/schemas/#{name}" }

  def json_response(description, schema)
    { description: description, content: { "application/json" => { schema: schema } } }
  end

  def error_response(code)
    { "$ref": "#/components/responses/#{code.to_s.camelize}" }
  end

  # Annotates a property with the scopes that expose it, so an agent can work
  # out the least-privilege scope set for the fields it actually needs.
  def scoped(scopes, schema)
    return schema if scopes.blank?

    schema.merge("x-scopes": scopes)
  end
end
