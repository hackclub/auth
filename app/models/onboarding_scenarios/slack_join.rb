module OnboardingScenarios
  class SlackJoin < Base
    def self.slug = "slack"

    def title
      "Join the Hack Club Slack!"
    end

    def form_fields
      [ :first_name, :last_name, :primary_email, :birthday, :country ]
    end

    def slack_user_type
      Flipper.enabled?(:full_user_open_floodgates_2026_04_06, @identity) ? :full_member : :multi_channel_guest
    end

    def next_action = :slack

    def slack_onboarding_flow = :internal_tutorial

    def first_step
      slack_user_type == :full_member ? :welcome : :intro
    end

    def slack_channels
      channels = Rails.configuration.slack_channels.slice(:welcome_to_hack_club).values
      channels += promotion_channels if slack_user_type == :full_member
      channels
    end

    def promotion_channels = Rails.configuration.slack_channels.slice(:announcements, :happenings, :community, :hardware, :code, :ship, :neighbourhood, :library, :lounge, :help).values

    def send_ephemeral_in_channel? = true

    def ephemeral_channel = Rails.configuration.slack_channels[:welcome_to_hack_club]
  end
end
