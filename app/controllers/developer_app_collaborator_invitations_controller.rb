class DeveloperAppCollaboratorInvitationsController < ApplicationController
  include IdentityAuthorizable

  before_action :set_app
  skip_after_action :verify_authorized, only: %i[accept decline]

  # Invitee accepts
  def accept
    invitation = current_identity.pending_collaboration_invitations.find(params[:id])
    invitation.update!(identity: current_identity) if invitation.identity_id.nil?
    invitation.accept!
    redirect_to developer_apps_path, notice: t(".success")
  end

  # Invitee declines
  def decline
    invitation = current_identity.pending_collaboration_invitations.find(params[:id])
    invitation.decline!
    redirect_to developer_apps_path, notice: t(".success")
  end

  # Owner cancels
  def cancel
    authorize @app, :manage_collaborators?
    invitation = @app.program_collaborators.pending.find(params[:id])
    invitation.cancel!
    redirect_to developer_app_path(@app), notice: t(".success")
  end

  private

  def set_app
    @app = Program.find(params[:developer_app_id])
  end
end
