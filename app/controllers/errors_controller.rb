class ErrorsController < ApplicationController
  skip_before_action :authenticate_identity!
  layout "minimal"

  def not_found
    @event_id = request.env["sentry.error_event_id"]
    render status: :not_found
  end

  def unprocessable_entity
    @event_id = request.env["sentry.error_event_id"]
    render status: :unprocessable_entity
  end

  def internal_server_error
    @event_id = request.env["sentry.error_event_id"]
    render status: :internal_server_error
  end
end
