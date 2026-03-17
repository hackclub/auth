class AssignSlackWorkspaceJob < ApplicationJob
  queue_as :default

  def perform(slack_id:, user_type:, channel_ids:, identity_id: nil)
    Rails.logger.info "Assigning Slack user #{slack_id} to workspace with channels #{channel_ids}"
    success = SlackService.assign_to_workspace(user_id: slack_id, user_type:, channel_ids:)

    if success && identity_id.present?
      identity = Identity.find_by(id: identity_id)
      identity&.update(is_in_workspace: true)
      Rails.logger.info "Marked identity #{identity_id} as in workspace"
    elsif !success
      identity = Identity.find_by(id: identity_id) if identity_id.present?
      Sentry.capture_message(
        "AssignSlackWorkspaceJob failed to assign user to workspace",
        level: :error,
        tags: { component: "slack", critical: true, operation: "assign_workspace_job" },
        extra: {
          slack_id: slack_id,
          user_type: user_type,
          channel_ids: channel_ids,
          identity_id: identity_id,
          identity_public_id: identity&.public_id,
          identity_email: identity&.primary_email,
          onboarding_scenario: identity&.onboarding_scenario,
          is_in_workspace: identity&.is_in_workspace,
          team_id: SlackService.team_id
        }
      )
    end
  end
end
