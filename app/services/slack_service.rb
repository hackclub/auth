module SlackService
  class << self
    def client = @client ||= Slack::Web::Client.new

    def user_client = @user_client ||= Slack::Web::Client.new(token: SCIMService.scim_token)

    def team_id = @team_id ||= ENV["SLACK_TEAM_ID"] || raise("SLACK_TEAM_ID not configured")

    def find_by_email(email)
      client.users_lookupByEmail(email:).dig("user", "id")
    rescue => e
      Rails.logger.warn "Could not find Slack user by email #{email}: #{e.message}"
      nil
    end

    def assign_to_workspace(user_id:, channel_ids: nil, user_type: :full_member)
      is_restricted = user_type == :multi_channel_guest
      is_ultra_restricted = user_type == :single_channel_guest

      user_client.admin_users_assign(
        user_id:,
        team_id:,
        channel_ids: channel_ids.join(","),
        is_restricted:,
        is_ultra_restricted:
      )

      Rails.logger.info "Assigned Slack user #{user_id} to workspace #{team_id}"
      true
    rescue => e
      Rails.logger.error "Failed to assign user to workspace: #{e.message}"
      false
    end

    def promote_user(user_id)
      user_client.admin_users_setRegular(team_id:, user_id:)
      Rails.logger.info "Promoted Slack user #{user_id} to full member"
      true
    rescue => e
      Rails.logger.error "Failed to promote user: #{e.message}"
      false
    end

    def add_to_channels(user_id:, channel_ids:)
      Array(channel_ids).each do |channel_id|
        client.conversations_invite(channel: channel_id, users: user_id)
        Rails.logger.info "Added user #{user_id} to channel #{channel_id}"
      end
      true
    rescue => e
      Rails.logger.error "Failed to add user to channels: #{e.message}"
      false
    end
  end
end
