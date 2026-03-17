class DeveloperAppCollaboratorInvitationsController < ApplicationController
  include IdentityAuthorizable

  before_action :set_invitation

  # Invitee accepts
  def accept
    authorize @invitation
    @invitation.update!(identity: current_identity) if @invitation.identity_id.nil?
    @invitation.accept!
    @invitation.program.create_activity :collaborator_accepted, owner: current_identity
    redirect_to developer_apps_path, notice: t(".success")
  end

  # Invitee declines
  def decline
    authorize @invitation
    @invitation.decline!
    @invitation.program.create_activity :collaborator_declined, owner: current_identity
    redirect_to developer_apps_path, notice: t(".success")
  end

  # Owner cancels
  def cancel
    authorize @invitation
    email = @invitation.invited_email
    @invitation.cancel!
    @invitation.program.create_activity :collaborator_cancelled, owner: current_identity, parameters: { cancelled_email: email }
    redirect_to developer_app_path(@invitation.program), notice: t(".success")
  end

  private

  def set_invitation
    @invitation = ProgramCollaborator.find(params[:id])
  end
end
