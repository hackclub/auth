class AuditLogsController < ApplicationController
  def index
    @activities = PublicActivity::Activity
      .where("(recipient_id = ? AND recipient_type = ?) OR (owner_id = ? AND owner_type = ?)",
             current_identity.id, "Identity", current_identity.id, "Identity")
      .order(created_at: :desc)
      .page(params[:page])
      .per(50)

    render layout: request.headers["HX-Request"] ? "htmx" : "application"
  end
end
