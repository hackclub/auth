# frozen_string_literal: true

# The catalog of machine-readable error codes the JSON API can return.
#
# Every API error body has the same shape:
#
#   { "error": "invalid_auth",          # stable code — branch on this
#     "message": "…",                   # human-readable
#     "hint": "…",                      # how to fix it
#     "status": 401,
#     "documentation_url": "https://auth.hackclub.com/docs/api" }
#
# The `error` codes for existing endpoints are unchanged; `message`, `hint`,
# `status` and `documentation_url` are additive.
module APIErrors
  DOCS_PATH = "/docs/api"

  # Paths whose callers are machines, not browsers. Requests under these get a
  # structured JSON error even when the client sends no Accept header.
  PATH_PREFIXES = %w[/api /oauth /.well-known /openapi].freeze

  CATALOG = {
    bad_request: {
      status: 400,
      message: "The request could not be understood.",
      hint: "Check the request body and query parameters against the OpenAPI description at /openapi.json."
    },
    param_missing: {
      status: 400,
      message: "A required parameter is missing.",
      hint: "The message names the missing parameter. See /openapi.json for each endpoint's required parameters."
    },
    invalid_auth: {
      status: 401,
      message: "The access token is missing, malformed, expired or revoked.",
      hint: "Send a valid credential as `Authorization: Bearer <token>`. Obtain one via the authorization code flow at /oauth/authorize, or refresh it at /oauth/token."
    },
    not_authorized: {
      status: 403,
      message: "The credential is valid but is not permitted to perform this action.",
      hint: "Check the scopes granted to your token, and whether the endpoint requires a program key. Scopes are listed at /.well-known/oauth-protected-resource."
    },
    not_found: {
      status: 404,
      message: "The requested resource does not exist, or your credential cannot see it.",
      hint: "Verify the identifier. Identities that have not authorized your program are reported as not found."
    },
    method_not_allowed: {
      status: 405,
      message: "That HTTP method is not supported for this path.",
      hint: "See /openapi.json for the methods each path accepts."
    },
    unprocessable_entity: {
      status: 422,
      message: "The request was well-formed but could not be processed.",
      hint: "The message describes which value was rejected."
    },
    rate_limited: {
      status: 429,
      message: "Too many requests.",
      hint: "Back off and retry later. Honour the Retry-After header when present."
    },
    server_error: {
      status: 500,
      message: "Something went wrong on our end.",
      hint: "Retry the request. If it keeps failing, get in touch via /docs/contact."
    }
  }.freeze

  module_function

  # Does this path belong to the machine-facing surface?
  def api_path?(path)
    return false if path.blank?

    PATH_PREFIXES.any? { |prefix| path == prefix || path.start_with?("#{prefix}/", "#{prefix}.") }
  end

  def status_for(code) = CATALOG.fetch(code.to_sym).fetch(:status)

  # Builds the JSON body for an error code. `message` and `hint` may be
  # overridden to add detail specific to the failed request.
  def body(code, base_url:, message: nil, hint: nil)
    definition = CATALOG.fetch(code.to_sym)

    {
      error: code.to_s,
      message: message.presence || definition[:message],
      hint: hint.presence || definition[:hint],
      status: definition[:status],
      documentation_url: "#{base_url.to_s.chomp('/')}#{DOCS_PATH}"
    }.compact
  end

  # Maps an exception class to a catalog code, so unhandled-but-known
  # exceptions still produce a structured body instead of an HTML page.
  def code_for_exception(exception)
    case exception
    when ActionController::ParameterMissing then :param_missing
    when ActiveRecord::RecordNotFound, ActionController::RoutingError then :not_found
    when ActionController::UnknownHttpMethod, ActionController::MethodNotAllowed then :method_not_allowed
    when ActiveRecord::RecordInvalid then :unprocessable_entity
    when ActionController::BadRequest then :bad_request
    else :server_error
    end
  end

  # Maps an HTTP status to a catalog code, for the error pages that only know
  # the status Rails settled on.
  def code_for_status(status)
    CATALOG.find { |_code, definition| definition[:status] == status.to_i }&.first || :server_error
  end
end
