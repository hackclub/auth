module OnboardingScenarios
  class Game < Base
    def self.slug = "beest"

    def title = "Welcome to Hack Club Beest"

    def form_fields
      [ :first_name, :last_name, :primary_email, :birthday, :country ]
    end

    def slack_user_type = :multi_channel_guest

    def slack_channels = chans(:beest, :beest_bulletin, :beest_help, :welcome_to_hack_club)

    def slack_onboarding_flow = :internal_tutorial

    def next_action = :home

    def background_path = "images/beest/background.png"
  end
end
