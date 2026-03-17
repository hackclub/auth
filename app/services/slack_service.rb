module SlackService
  class << self
    def client = @client ||= Slack::Web::Client.new

    def user_client = @user_client ||= Slack::Web::Client.new(token: SCIMService.scim_token)

    def team_id = @team_id ||= ENV["SLACK_TEAM_ID"] || raise("SLACK_TEAM_ID not configured")

    def find_by_email(email)
      client.users_lookupByEmail(email:).dig("user", "id")
    rescue => e
      Rails.logger.warn "Could not find Slack user by email #{email}: #{e.message}" unless e.message == "users_not_found"
      unless e.message == "users_not_found"
        Sentry.capture_exception(e, tags: { component: "slack" }, extra: { email: email })
      end
      nil
    end

    def assign_to_workspace(user_id:, channel_ids: nil, user_type: :full_member)
      is_restricted = user_type == :multi_channel_guest
      is_ultra_restricted = user_type == :single_channel_guest

      user_client.admin_users_assign(
        user_id:,
        team_id:,
        channel_ids: channel_ids&.join(","),
        is_restricted:,
        is_ultra_restricted:
      )

      Rails.logger.info "Assigned Slack user #{user_id} to workspace #{team_id}"
      true
    rescue => e
      Rails.logger.error "Failed to assign user to workspace: #{e.message}"
      Sentry.capture_exception(e,
        level: :error,
        tags: { component: "slack", critical: true, operation: "assign_to_workspace" },
        extra: {
          slack_user_id: user_id,
          team_id: team_id,
          channel_ids: channel_ids,
          user_type: user_type,
          is_restricted: is_restricted,
          is_ultra_restricted: is_ultra_restricted
        }
      )
      false
    end

    def promote_user(user_id)
      user_client.admin_users_setRegular(team_id:, user_id:)
      Rails.logger.info "Promoted Slack user #{user_id} to full member"
      true
    rescue => e
      Rails.logger.error "Failed to promote user: #{e.message}"
      Sentry.capture_exception(e,
        level: :error,
        tags: { component: "slack", critical: true, operation: "promote_user" },
        extra: {
          slack_user_id: user_id,
          team_id: team_id
        }
      )
      false
    end

    def add_to_channels(user_id:, channel_ids:)
      failed = []
      Array(channel_ids).each do |channel_id|
        begin
          client.conversations_invite(channel: channel_id, users: user_id)
          Rails.logger.info "Added user #{user_id} to channel #{channel_id}"
        rescue => e
          Rails.logger.error "Failed to add user #{user_id} to channel #{channel_id}: #{e.message}"
          Sentry.capture_exception(e,
            level: :error,
            tags: { component: "slack", operation: "add_to_channels" },
            extra: { slack_user_id: user_id, channel_id: channel_id }
          )
          failed << channel_id
        end
      end
      failed.empty?
    end

    def user_workspace_status(user_id:)
      response = client.users_info(user: user_id)
      user = response.dig("user")

      return :unknown unless user
      return :deactivated if user["deleted"]

      teams = user["teams"] || []
      teams.include?(team_id) ? :in_workspace : :not_in_workspace
    rescue => e
      Rails.logger.warn "Could not check workspace status for user #{user_id}: #{e.message}"
      Sentry.capture_exception(e, tags: { component: "slack" }, extra: { slack_user_id: user_id })
      :unknown
    end
  end
end
