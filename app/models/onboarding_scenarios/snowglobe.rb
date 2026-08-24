module OnboardingScenarios
  class Snowglobe < Base
    def self.slug = "snowglobe"

    def title = "Come frolick in the snow!"

    def form_fields = [ :first_name, :last_name, :primary_email, :birthday, :country ]

    def slack_user_type = :full_member

    def slack_onboarding_flow = :internal_tutorial
    def slack_channels = chans(:athena_initiative, :welcome_to_athena, :athena_announcements, :snowglobe)

    def next_action = :home

    def logo_path = "images/snowglobe/logo.png"
    def background_path = "images/snowglobe/bg.png"
    def dark_mode_background_path = "images/snowglobe/bg.png"

    def first_step = :welcome

    def dialogue_flow
      {
        welcome: { template: "tutorial/snowglobe/intro", next: nil }
      }
    end
  end
end
