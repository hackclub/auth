module OnboardingScenarios
  class Stardance < Base
    def self.slug = "stardance"

    def title = "get ready for launch!"

    def form_fields
      [ :first_name, :last_name, :primary_email, :birthday, :country ]
    end

    def slack_channels = chans(:stardance_help, :identity_help, :hackatime_help, :help, :stardance_bulletin, :planet, :welcome_to_hack_club)

    def promotion_channels = chans(:stardance, :library, :lounge, :welcome, :happenings, :community, :announcements)

    def logo_path = "images/stardance/logo.png"
    def background_path = "images/stardance/hero-bg.png"
  end
end
