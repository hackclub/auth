module OnboardingScenarios
  class SlackJoin < Base
    def self.slug = "slack"

    def title
      "Join the Hack Club Slack!"
    end

    def form_fields
      [ :first_name, :last_name, :primary_email, :birthday, :country ]
    end

    def slack_user_type = :multi_channel_guest

    def next_action = :slack

    def slack_onboarding_flow = :internal_tutorial

    def slack_channels = Rails.configuration.slack_channels.slice(:welcome_to_hack_club).values

    def promotion_channels = Rails.configuration.slack_channels.slice(:announcements, :welcome, :ship, :neighbourhood, :library, :lounge).values
  end
end
