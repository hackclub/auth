class ErrorsController < ActionController::Base
  layout "errors"

  def not_found
    render_error :not_found, template: "errors/not_found"
  end

  def unprocessable_entity
    render_error :unprocessable_entity, template: "errors/unprocessable_entity"
  end

  def internal_server_error
    render_error :internal_server_error, template: "errors/internal_server_error"
  end

  private

  def render_error(status, template:)
    @event_id = request.env["sentry.error_event_id"]

    # Both the body and the negotiation decision are computed up front, so the
    # rescue below can never re-run the code that just failed.
    json = wants_json?
    body = json ? safe_error_body(status) : nil

    if json
      render json: body, status: status, content_type: "application/json"
    else
      render template, status: status
    end
  rescue StandardError
    # Last resort: never let the error page raise its own error. Nothing here
    # may call back into error_body/wants_json? — `body` and `json` are already
    # resolved, and the plain-text fallbacks cannot raise.
    if json
      render json: (body || minimal_error_body(status)).to_json,
             status: status, content_type: "application/json"
    else
      render plain: "#{Rack::Utils.status_code(status)} - #{status.to_s.titleize}", status: status
    end
  end

  # error_body touches the request and the APIErrors catalog; if either misbehaves
  # we still owe the client a parseable body.
  def safe_error_body(status)
    error_body(status)
  rescue StandardError
    minimal_error_body(status)
  end

  def minimal_error_body(status)
    code = Rack::Utils.status_code(status) == 404 ? "not_found" : "server_error"
    { error: code, status: Rack::Utils.status_code(status) }
  end

  def error_body(status)
    code = APIErrors.code_for_status(Rack::Utils.status_code(status))
    body = APIErrors.body(code, base_url: request.base_url)
    body[:message] = "No endpoint matches #{original_request_method} #{original_path}." if code == :not_found && original_path.present?
    body[:hint] = "The available endpoints are listed at #{request.base_url}/api and described at #{request.base_url}/openapi.json." if code == :not_found
    body[:sentry_event_id] = @event_id if @event_id.present?
    body
  end

  def wants_json?
    return true if api_path?

    request.format.to_s.include?("json")
  rescue StandardError
    # A malformed Accept header shouldn't decide anything; fall back to HTML.
    false
  end

  def api_path? = APIErrors.api_path?(original_path)

  # With `config.exceptions_app = routes`, Rails rewrites PATH_INFO to /404 (or
  # /422, /500) and stashes the real request under these keys.
  def original_path = request.env["action_dispatch.original_path"].presence || request.path

  def original_request_method
    request.env["action_dispatch.original_request_method"].presence || request.request_method
  end
end
