module OnboardingScenarios
  class Crescent < Base
    def self.slug = "crescent"

    def title = "Let's create a Hack Club Account!"

    def form_fields = [ :first_name, :last_name, :primary_email, :birthday, :country ]

    def slack_user_type = :full_member

    def slack_onboarding_flow = :internal_tutorial
    def slack_channels = chans(:crescent_bulletin, :crescent_help, :crescent_chat,:identity_help, :help, :welcome_to_hack_club, :slack_guide, :library, :lounge, :welcome, :happenings, :community, :announcements, :news_wire)

    def first_step = :welcome

    def next_action = :home

    def logo_path = "images/crescent/logo.png"
    def background_path = "images/crescent/bg.jpg"

    def card_attributes = { wide_logo: true }
  end
end
