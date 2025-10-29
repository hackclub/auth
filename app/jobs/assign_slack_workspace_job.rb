class AssignSlackWorkspaceJob < ApplicationJob
  queue_as :default

  def perform(slack_id:, user_type:, channel_ids:, identity_id: nil)
    Rails.logger.info "Assigning Slack user #{slack_id} to workspace with channels #{channel_ids}"
    success = SlackService.assign_to_workspace(user_id: slack_id, user_type:, channel_ids:)

    if success && identity_id.present?
      identity = Identity.find_by(id: identity_id)
      identity&.update(is_in_workspace: true)
      Rails.logger.info "Marked identity #{identity_id} as in workspace"
    end
  end
end
