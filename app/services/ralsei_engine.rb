module RalseiEngine
  class << self
    RALSEI_PFP = "https://cdn.hackclub.com/019c2993-4a83-73d4-9e3a-96cf29881572/flaming_skull.jpg"

    def send_first_message(identity)
      scenario = identity.onboarding_scenario_instance
      scenario&.before_first_message
      first_step = scenario&.first_step || :intro
      send_step(identity, first_step)

      # Also send ephemeral message in channel if scenario requests it
      if scenario&.send_ephemeral_in_channel? && scenario.ephemeral_channel
        template = scenario.template_for(first_step)
        send_ephemeral_message(identity, template, scenario.ephemeral_channel)
      end

      Tutorial::ScrollUpReminderJob.set(wait: 25.seconds).perform_later(identity)
    end

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

      track_dialogue_event("dialogue.promoted", scenario: scenario&.class&.slug)
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
      raise "No onboarding scenario for identity #{identity.public_id}" unless scenario

      # Track first interaction (before processing, when count is 0)
      if identity.promote_click_count == 0
        track_dialogue_event("dialogue.first_interaction", scenario: scenario.class.slug)
      end

      result = scenario.handle_action(action_id)
      raise "Unknown action #{action_id} for scenario #{scenario.class.name}" unless result

      case result
      when Symbol
        send_step(identity, result)
      when String
        send_message(identity, result)
      when Hash
        promote_user(identity) if result[:promote]
        send_step(identity, result[:step]) if result[:step]
        send_message(identity, result[:template]) if result[:template]
        identity.increment!(:promote_click_count, 1) if result[:promote]
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

      track_dialogue_event("dialogue.promoted", scenario: scenario&.class&.slug)
      scenario&.after_promotion
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
        username: scenario&.bot_name || "The Flaming Skull of Welcome",
        icon_url: scenario&.bot_icon_url || RALSEI_PFP,
        **JSON.parse(payload, symbolize_names: true),
        unfurl_links: false,
      )

      Rails.logger.info "RalseiEngine sent message to #{identity.slack_id} via #{channel_id} (template: #{template_name})"
    rescue => e
      Rails.logger.error "RalseiEngine failed to send message: #{e.message}"
      Sentry.capture_exception(e,
        level: :error,
        tags: { component: "slack", critical: true, operation: "ralsei_send_message" },
        extra: {
          identity_public_id: identity.public_id,
          ralsei_template: template_name
        }
      )
      raise
    end

    def send_ephemeral_message(identity, template_name, channel_id)
      return unless identity.slack_id.present?
      return unless channel_id

      scenario = identity.onboarding_scenario_instance
      payload = render_template("slack/#{template_name}", identity)

      client.chat_postEphemeral(
        channel: channel_id,
        user: identity.slack_id,
        username: scenario&.bot_name || "The Flaming Skull of Welcome",
        icon_url: scenario&.bot_icon_url || RALSEI_PFP,
        **JSON.parse(payload, symbolize_names: true),
        unfurl_links: false,
      )

      Rails.logger.info "RalseiEngine sent ephemeral message to #{identity.slack_id} in #{channel_id} (template: #{template_name})"
    rescue => e
      Rails.logger.error "RalseiEngine failed to send ephemeral message: #{e.message}"
      Sentry.capture_exception(e,
        level: :error,
        tags: { component: "slack", critical: true, operation: "ralsei_send_ephemeral_message" },
        extra: {
          identity_public_id: identity.public_id,
          ralsei_template: template_name,
          channel_id: channel_id
        }
      )
      raise
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
      Sentry.capture_exception(e,
        level: :error,
        tags: { component: "slack", critical: true, operation: "ralsei_open_dm" },
        extra: {
          identity_public_id: identity.public_id
        }
      )
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

    # Track dialogue events directly (no request context in background jobs)
    def track_dialogue_event(name, properties = {})
      return if ENV["DISABLE_ANALYTICS"] == "true"

      Ahoy::Event.create!(
        name: name,
        properties: properties,
        time: Time.current
      )
    rescue
      # Silently ignore analytics failures
    end
  end
end
