class AuthorizedApplicationsController < ApplicationController
  def index
    @access_tokens = current_identity.access_tokens
      .includes(:application)
      .order(created_at: :desc)

    render layout: request.headers["HX-Request"] ? "htmx" : false
  end

  def destroy
    token = current_identity.access_tokens.find(params[:id])
    token.revoke

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
