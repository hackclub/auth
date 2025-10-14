class IdentitySessionsController < ApplicationController
  def index
    @sessions = current_identity.sessions
      .where(signed_out_at: nil)
      .where("expires_at > ?", Time.current)
      .order(last_seen: :desc)
    @current_session = current_session

    render layout: request.headers["HX-Request"] ? "htmx" : false
  end

  def destroy
    session = current_identity.sessions.not_expired.find(params[:id])
    session.update!(signed_out_at: Time.now, expires_at: Time.now)

    if request.headers["HX-Request"]
      @sessions = current_identity.sessions
        .where(signed_out_at: nil)
        .where("expires_at > ?", Time.current)
        .order(last_seen: :desc)
      @current_session = current_session

      flash.now[:success] = "Session logged out successfully"
      render :index, layout: "htmx"
    else
      flash[:success] = "Session terminated."
      redirect_to security_path
    end
  end

  def destroy_all
    current_identity.sessions
      .where(signed_out_at: nil)
      .not_expired
      .where.not(id: current_session&.id)
      .update_all(signed_out_at: Time.current, expires_at: Time.now)

    if request.headers["HX-Request"]
      @sessions = current_identity.sessions
        .where(signed_out_at: nil)
        .where("expires_at > ?", Time.current)
        .order(last_seen: :desc)
      @current_session = current_session

      flash.now[:success] = "All other sessions logged out successfully"
      render :index, layout: "htmx"
    else
      flash[:success] = "All other sessions terminated."
      redirect_to security_path
    end
  end
end
