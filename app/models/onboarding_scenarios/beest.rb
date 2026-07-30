module OnboardingScenarios
  class Beest < Base
    def self.slug = "beest"

    def title = "Welcome to Hack Club Beest"

    def form_fields = [ :first_name, :last_name, :primary_email, :birthday, :country ]

    def slack_user_type = :full_member

    def slack_channels = chans(:beest, :beest_bulletin, :beest_help, :identity_help, :help, :welcome_to_hack_club, :slack_guide, :library, :lounge, :welcome, :happenings, :community, :announcements, :news_wire)

    def first_step = :welcome

    def slack_onboarding_flow = :internal_tutorial

    def next_action = :home

    def background_path = "images/beest/background.png"
  end
end
