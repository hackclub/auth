class ErrorsController < ApplicationController
  skip_before_action :authenticate_identity!
  skip_before_action :set_honeybadger_context

  # Skip rescue_from handlers to prevent error loops
  skip_around_action :handle_errors, raise: false

  layout "errors"

  def not_found
    @event_id = request.env["sentry.error_event_id"]
    render status: :not_found
  rescue => e
    # Last resort: render plain text to avoid infinite loops
    render plain: "404 - Page Not Found", status: :not_found
  end

  def unprocessable_entity
    @event_id = request.env["sentry.error_event_id"]
    render status: :unprocessable_entity
  rescue => e
    render plain: "422 - Unprocessable Entity", status: :unprocessable_entity
  end

  def internal_server_error
    @event_id = request.env["sentry.error_event_id"]
    render status: :internal_server_error
  rescue => e
    render plain: "500 - Internal Server Error", status: :internal_server_error
  end
end
