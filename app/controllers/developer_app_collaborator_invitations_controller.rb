class DeveloperAppCollaboratorInvitationsController < ApplicationController
  include IdentityAuthorizable

  before_action :set_app
  skip_after_action :verify_authorized, only: %i[accept decline]

  # Invitee accepts
  def accept
    invitation = current_identity.pending_collaboration_invitations.find(params[:id])
    invitation.update!(identity: current_identity) if invitation.identity_id.nil?
    invitation.accept!
    @app.create_activity :collaborator_accepted, owner: current_identity
    redirect_to developer_apps_path, notice: t(".success")
  end

  # Invitee declines
  def decline
    invitation = current_identity.pending_collaboration_invitations.find(params[:id])
    invitation.decline!
    @app.create_activity :collaborator_declined, owner: current_identity
    redirect_to developer_apps_path, notice: t(".success")
  end

  # Owner cancels
  def cancel
    authorize @app, :manage_collaborators?
    invitation = @app.program_collaborators.pending.find(params[:id])
    email = invitation.invited_email
    invitation.cancel!
    @app.create_activity :collaborator_cancelled, owner: current_identity, parameters: { cancelled_email: email }
    redirect_to developer_app_path(@app), notice: t(".success")
  end

  private

  def set_app
    @app = Program.find(params[:developer_app_id])
  end
end
