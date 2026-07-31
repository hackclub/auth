module OnboardingScenarios
  class Athena < Base
    def self.slug = "athena"

    def title = "join the athena community!"

    def form_fields = [ :first_name, :last_name, :primary_email, :birthday, :country ]

    def slack_user_type = :full_member

    def slack_onboarding_flow = :internal_tutorial
    def slack_channels = chans(:athena_initiative, :welcome_to_athena, :athena_announcements)

    def next_action = :slack

    def logo_path = "images/athena/athenaLogo.png"
    def background_path = "images/athena/bg-img.png"
    def dark_mode_background_path = "images/athena/bg-img.png"

    def first_step = :welcome

    def dialogue_flow
      {
        welcome: { template: "tutorial/athena/intro", next: nil }
      }
    end
  end
end
