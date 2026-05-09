module OnboardingScenarios
  class Stickers < Base
    def self.slug = "stickers"

    def title = "Welcome to Stickers"

    def form_fields
      [ :first_name, :last_name, :primary_email, :birthday, :country ]
    end

    def slack_channels = chans(:stickers, :stickers_bulletin, :stickers_help, :welcome_to_hack_club, :help)

    def slack_onboarding_flow = :internal_tutorial

    def next_action = :home

    def logo_path = "images/stickers/logo.png"
    def background_path = "images/stickers/background.png"

    def card_attributes = { wide_logo: true }
  end
end
