module RalseiEngine
  class << self
    RALSEI_PFP = "https://hc-cdn.hel1.your-objectstorage.com/s/v3/6cc8caeeff906502bfe60ba2f3db34cdf79a237d_ralsei2.png"

    def send_first_message(identity) = send_message(identity, "tutorial/01_intro")

    def send_first_message_part2(identity) = send_message(identity, "tutorial/02_hacker_values")

    def handle_tutorial_agree(identity)
      Rails.logger.info "RalseiEngine: #{identity.public_id} agreed to tutorial"

      if identity.promote_click_count == 0
        SlackService.promote_user(identity.slack_id)

        promotion_channels = identity.onboarding_scenario_instance.promotion_channels
        if promotion_channels.present?
          SlackService.add_to_channels(user_id: identity.slack_id, channel_ids: promotion_channels)
        end
      else
        Rails.logger.info "RalseiEngine: #{identity.public_id} is already a full member"
      end
      send_message(identity, "tutorial/03_welcome")
      identity.increment!(:promote_click_count, 1)
    end

    def send_message(identity, template_name)
      return unless identity.slack_id.present?

      payload = render_template("slack/#{template_name}", identity)

      client.chat_postMessage(
        channel: identity.slack_id,
        username: "Ralsei",
        icon_url: RALSEI_PFP,
        **JSON.parse(payload, symbolize_names: true),
        unfurl_links: false,
      )

      Rails.logger.info "RalseiEngine sent message to #{identity.slack_id} (template: #{template_name})"
    rescue => e

      Rails.logger.error "RalseiEngine failed to send message: #{e.message}"
      Honeybadger.notify(e, context: { identity_id: identity.id, template: template_name })
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
