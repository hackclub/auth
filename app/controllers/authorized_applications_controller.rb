class AuthorizedApplicationsController < ApplicationController
  include AhoyAnalytics

  def index
    @authorized_apps = load_apps
    render layout: htmx? ? "htmx" : false
  end

  def destroy
    t = current_identity.access_tokens.find(params[:id])
    app = t.application

    track_event("oauth.revoked", program_name: app&.name, program_id: app&.id, scenario: app&.onboarding_scenario)

    n = current_identity.all_access_tokens.where(application_id: app.id, revoked_at: nil).count
    Program.revoke_tokens_and_grants_for(app.id, current_identity)
    t.create_activity :revoke, owner: current_identity, recipient: current_identity,
      parameters: { application_id: app.id, tokens_revoked: n }

    if htmx?
      @authorized_apps = load_apps
      flash.now[:success] = "Application access revoked successfully"
      render :index, layout: "htmx"
    else
      flash[:success] = "Application access revoked."
      redirect_to security_path
    end
  end

  private

  def htmx? = request.headers["HX-Request"].present?

  def load_apps
    current_identity.access_tokens.includes(:application).order(created_at: :desc).to_a
      .group_by(&:application_id)
      .filter_map { |_, toks|
        tok = toks.first
        next unless tok&.application
        {
          token: tok,
          application: tok.application,
          authorized_at: toks.map(&:created_at).min,
          expires_at: toks.filter_map(&:expires_at).min,
          scopes: toks.flat_map { |x| x.scopes.to_a }.uniq
        }
      }
      .sort_by { |e| e[:authorized_at] }.reverse
  end
end
