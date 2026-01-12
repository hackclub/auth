class AuthorizedApplicationsController < ApplicationController
  include AhoyAnalytics

  def index
    @access_tokens = current_identity.access_tokens
      .includes(:application)
      .order(created_at: :desc)

    render layout: request.headers["HX-Request"] ? "htmx" : false
  end

  def destroy
    token = current_identity.access_tokens.find(params[:id])
    track_event("oauth.revoked", program_slug: token.application&.slug, scenario: analytics_scenario_for(current_identity))
    token.revoke
    token.create_activity :revoke, owner: current_identity, recipient: current_identity

    if request.headers["HX-Request"]
      @access_tokens = current_identity.access_tokens
        .includes(:application)
        .order(created_at: :desc)

      flash.now[:success] = "Application access revoked successfully"
      render :index, layout: "htmx"
    else
      flash[:success] = "Application access revoked."
      redirect_to security_path
    end
  end
end
