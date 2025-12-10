module RalseiEngine
  class << self
    RALSEI_PFP = "https://hc-cdn.hel1.your-objectstorage.com/s/v3/6cc8caeeff906502bfe60ba2f3db34cdf79a237d_ralsei2.png"

    def send_first_message(identity)
      scenario = identity.onboarding_scenario_instance
      scenario&.before_first_message
      first_step = scenario&.first_step || :intro
      send_step(identity, first_step)
    end

    def send_first_message_part2(identity) = send_step(identity, :hacker_values)

    def handle_tutorial_agree(identity)
      Rails.logger.info "RalseiEngine: #{identity.public_id} agreed to tutorial"
      scenario = identity.onboarding_scenario_instance

      if identity.promote_click_count == 0
        SlackService.promote_user(identity.slack_id)

        promotion_channels = scenario&.promotion_channels
        if promotion_channels.present?
          SlackService.add_to_channels(user_id: identity.slack_id, channel_ids: promotion_channels)
        end
      else
        Rails.logger.info "RalseiEngine: #{identity.public_id} is already a full member"
      end

      scenario&.after_promotion
      send_step(identity, :welcome)
      identity.increment!(:promote_click_count, 1)
    end

    def send_step(identity, step)
      scenario = identity.onboarding_scenario_instance
      template = scenario&.template_for(step) || "tutorial/#{step}"
      send_message(identity, template)
    end

    def advance_to_next(identity, current_step)
      scenario = identity.onboarding_scenario_instance
      next_step = scenario&.next_step(current_step)
      send_step(identity, next_step) if next_step
      next_step
    end

    def handle_action(identity, action_id)
      scenario = identity.onboarding_scenario_instance
      return false unless scenario

      result = scenario.handle_action(action_id)
      return false unless result

      case result
      when Symbol
        send_step(identity, result)
      when String
        send_message(identity, result)
      when Hash
        promote_user(identity) if result[:promote]
        send_step(identity, result[:step]) if result[:step]
        send_message(identity, result[:template]) if result[:template]
      end

      true
    end

    def promote_user(identity)
      return if identity.promote_click_count > 0

      scenario = identity.onboarding_scenario_instance
      SlackService.promote_user(identity.slack_id)

      promotion_channels = scenario&.promotion_channels
      if promotion_channels.present?
        SlackService.add_to_channels(user_id: identity.slack_id, channel_ids: promotion_channels)
      end

      scenario&.after_promotion
      identity.increment!(:promote_click_count, 1)
      Rails.logger.info "RalseiEngine: promoted #{identity.public_id}"
    end

    def send_message(identity, template_name)
      return unless identity.slack_id.present?

      channel_id = resolve_channel(identity)
      return unless channel_id

      scenario = identity.onboarding_scenario_instance
      payload = render_template("slack/#{template_name}", identity)

      client.chat_postMessage(
        channel: channel_id,
        username: scenario&.bot_name || "Ralsei",
        icon_url: scenario&.bot_icon_url || RALSEI_PFP,
        **JSON.parse(payload, symbolize_names: true),
        unfurl_links: false,
      )

      Rails.logger.info "RalseiEngine sent message to #{identity.slack_id} via #{channel_id} (template: #{template_name})"
    rescue => e
      Rails.logger.error "RalseiEngine failed to send message: #{e.message}"
      Honeybadger.notify(e, context: { identity_id: identity.id, template: template_name })
    end

    def resolve_channel(identity)
      scenario = identity.onboarding_scenario_instance
      if scenario&.use_dm_channel?
        ensure_dm_channel(identity)
      else
        identity.slack_id
      end
    end

    def ensure_dm_channel(identity)
      return identity.slack_dm_channel_id if identity.slack_dm_channel_id.present?

      response = client.conversations_open(users: identity.slack_id)
      dm_channel_id = response.dig("channel", "id")

      if dm_channel_id
        identity.update!(slack_dm_channel_id: dm_channel_id)
        Rails.logger.info "RalseiEngine opened DM channel #{dm_channel_id} for #{identity.slack_id}"
      end

      dm_channel_id
    rescue => e
      Rails.logger.error "RalseiEngine failed to open DM channel: #{e.message}"
      Honeybadger.notify(e, context: { identity_id: identity.id })
      nil
    end

    private

    def render_template(template_name, identity)
      Slack::InteractivityController.render(
        template: template_name,
        formats: [ :slack_message ],
        assigns: { identity: identity }
      )
    end

    def client
      @client ||= SlackService.client
    end
  end
end
