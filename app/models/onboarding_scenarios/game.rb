module OnboardingScenarios
  class Game < Base
    def self.slug = "game"

    def title = "Welcome to The Game!"

    def form_fields
      [ :first_name, :last_name, :primary_email, :birthday, :country ]
    end

    def slack_channels = chans(:hack_club_the_game, :hctg_bulletin, :hctg_help, :welcome_to_hack_club)

    def slack_onboarding_flow = :internal_tutorial

    def next_action = :home

    def logo_path = "images/game/logo.png"
    def background_path = "images/game/background.png"

    def card_attributes = { wide_logo: true }
  end
end
