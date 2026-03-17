class DeveloperAppCollaboratorsController < ApplicationController
  include IdentityAuthorizable

  before_action :set_app

  def create
    authorize @app, :manage_collaborators?

    email = params[:email].to_s.strip.downcase

    if email == @app.owner_identity&.primary_email
      redirect_to developer_app_path(@app), alert: t(".cannot_add_self")
      return
    end

    identity = Identity.find_by(primary_email: email)

    collaborator = @app.program_collaborators.find_or_create_by(invited_email: email) do |pc|
      pc.identity = identity
    end

    unless collaborator.persisted?
      alert_message = collaborator.errors.full_messages.to_sentence.presence || t(".invalid_email")
      redirect_to developer_app_path(@app), alert: alert_message
      return
    end

    reinvitable = collaborator.may_reinvite?
    if reinvitable
      collaborator.identity = identity
      collaborator.reinvite!
    end

    if collaborator.previously_new_record? || reinvitable
      @app.create_activity :collaborator_invited, owner: current_identity, parameters: { invited_email: email }
      redirect_to developer_app_path(@app), notice: t(".invited")
    else
      redirect_to developer_app_path(@app), alert: t(".already_invited")
    end
  end

  def destroy
    collaborator = @app.program_collaborators.find(params[:id])
    authorize collaborator, :remove?
    email = collaborator.invited_email
    collaborator.remove!
    @app.create_activity :collaborator_removed, owner: current_identity, parameters: { removed_email: email }

    redirect_to developer_app_path(@app), notice: t(".success")
  end

  private

  def set_app
    @app = Program.find(params[:developer_app_id])
  rescue ActiveRecord::RecordNotFound
    flash[:error] = t("developer_apps.set_app.not_found")
    redirect_to developer_apps_path
  end
end
