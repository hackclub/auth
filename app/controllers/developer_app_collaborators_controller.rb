class DeveloperAppCollaboratorsController < ApplicationController
  include IdentityAuthorizable

  before_action :set_app

  def create
    authorize @app, :manage_collaborators?

    email = params[:email].to_s.strip.downcase

    # Anti-enumeration: always return the same generic message regardless of outcome
    identity = Identity.find_by(primary_email: email)

    if identity && identity != @app.owner_identity
      @app.program_collaborators.find_or_create_by(identity: identity)
    end

    redirect_to developer_app_path(@app), notice: t(".generic_response")
  end

  def destroy
    authorize @app, :manage_collaborators?

    collaborator = @app.program_collaborators.find(params[:id])
    collaborator.destroy

    redirect_to developer_app_path(@app), notice: t(".success")
  rescue ActiveRecord::RecordNotFound
    flash[:error] = t("developer_apps.collaborator.not_found")
    redirect_to developer_app_path(@app)
  end

  private

  def set_app
    @app = Program.find(params[:developer_app_id])
  rescue ActiveRecord::RecordNotFound
    flash[:error] = t("developer_apps.set_app.not_found")
    redirect_to developer_apps_path
  end
end
