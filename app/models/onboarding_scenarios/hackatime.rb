module OnboardingScenarios
  class Hackatime < Base
    def self.slug = "hackatime"

    def title
      "Sign in to Hackatime"
    end

    def form_fields
      [ :first_name, :last_name, :primary_email, :birthday, :country ]
    end

    def accepts_adults = true

    def should_create_slack? = @identity.birthday.present? && @identity.eighteen_or_under?

    def next_action = :home

    def slack_user_type = :multi_channel_guest
    def slack_onboarding_flow = :internal_tutorial
    def slack_channels = Rails.configuration.slack_channels.slice(:welcome_to_hack_club, :hackatime_dev, :hackatime_help).values
    def promotion_channels = Rails.configuration.slack_channels.slice(:announcements, :happenings, :community, :hardware, :code, :ship, :neighbourhood, :library, :lounge).values
    def send_ephemeral_in_channel? = true
    def ephemeral_channel = Rails.configuration.slack_channels[:welcome_to_hack_club]
  end
end
