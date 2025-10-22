class AssignSlackWorkspaceJob < ApplicationJob
  queue_as :default

  def perform(slack_id:, user_type:, channel_ids:)
    Rails.logger.info "Assigning Slack user #{slack_id} to workspace with channels #{channel_ids}"
    SlackService.assign_to_workspace(user_id: slack_id, user_type:, channel_ids:)
  end
end
