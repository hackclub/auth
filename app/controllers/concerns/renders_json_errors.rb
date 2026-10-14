# frozen_string_literal: true

# Gives an API controller a single, structured way to fail.
#
# Every error leaves as JSON in the shape described by APIErrors, and 401/403
# responses carry an RFC 6750 `WWW-Authenticate` challenge that points at the
# RFC 9728 protected resource metadata, so a client that has never seen our
# docs can still discover how to authenticate.
module RendersJsonErrors
  extend ActiveSupport::Concern

  REALM = "Hack Club Auth"

  included do
    rescue_from ActionController::ParameterMissing do |e|
      render_api_error :param_missing, message: e.message
    end

    rescue_from ActiveRecord::RecordNotFound do |_e|
      render_api_error :not_found
    end

    rescue_from Pundit::NotAuthorizedError do |_e|
      render_api_error :not_authorized
    end
  end

  def render_api_error(code, message: nil, hint: nil, oauth_error: nil)
    body = APIErrors.body(code, base_url: request.base_url, message: message, hint: hint)
    status = body[:status]

    challenge = www_authenticate_challenge(status, oauth_error, body[:message])
    response.set_header("WWW-Authenticate", challenge) if challenge

    render json: body, status: status
  end

  def protected_resource_metadata_url = "#{request.base_url}/.well-known/oauth-protected-resource"

  private

  def www_authenticate_challenge(status, oauth_error, description)
    error = oauth_error.presence || default_oauth_error(status)
    return nil unless error

    params = {
      realm: REALM,
      error: error,
      error_description: description,
      resource_metadata: protected_resource_metadata_url
    }

    "Bearer " + params.map { |key, value| %(#{key}="#{value.to_s.gsub('"', "'")}") }.join(", ")
  end

  def default_oauth_error(status)
    case status
    when 401 then "invalid_token"
    when 403 then "insufficient_scope"
    end
  end
end
