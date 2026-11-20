module OnboardingScenarios
  class Hackatime < Base
    def self.slug = "hackatime"

    def title = "Sign in to Hackatime"

    def form_fields = [ :first_name, :last_name, :primary_email, :birthday, :country ]

    def accepts_adults = true

    def should_create_slack? = @identity.age < 19

    def slack_channels = chans(:welcome_to_hack_club, :hackatime_dev, :hackatime_help)

    def promotion_channels = chans(:announcements, :happenings, :community, :hardware, :code, :ship, :neighbourhood, :library, :lounge)

    def send_ephemeral_in_channel? = true

    def ephemeral_channel = Rails.configuration.slack_channels[:welcome_to_hack_club]

    def background_path = "images/stardance/hero-bg.png"
  end
end
