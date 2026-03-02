class DeveloperAppCollaboratorsController < ApplicationController
  include IdentityAuthorizable

  before_action :set_app

  def create
    authorize @app, :manage_collaborators?

    email = params[:email].to_s.strip.downcase

    # Anti-enumeration: always create a pending record regardless of whether
    # the identity exists. The owner sees the same "Pending" row either way.
    identity = Identity.find_by(primary_email: email)

    unless identity&.id == @app.owner_identity_id
      @app.program_collaborators.find_or_create_by(invited_email: email) do |pc|
        pc.identity = identity
      end
      @app.create_activity :collaborator_invited, owner: current_identity, parameters: { invited_email: email }
    end

    redirect_to developer_app_path(@app), notice: t(".generic_response")
  end

  def destroy
    authorize @app, :manage_collaborators?

    collaborator = @app.program_collaborators.find(params[:id])
    email = collaborator.invited_email
    collaborator.destroy
    @app.create_activity :collaborator_removed, owner: current_identity, parameters: { removed_email: email }

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
