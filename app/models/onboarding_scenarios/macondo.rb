module OnboardingScenarios
  class Macondo < Base
    def self.slug = "macondo"

    def title = "time to go on an adventure!"

    def form_fields = [ :first_name, :last_name, :primary_email, :birthday, :country ]

    def slack_user_type = :full_member

    def slack_onboarding_flow = :internal_tutorial
    def slack_channels = chans(:macondo, :macondo_help, :macondo_announcements, :identity_help, :help, :welcome_to_hack_club, :slack_guide, :library, :lounge, :welcome, :happenings, :community, :announcements, :news_wire)

    def first_step = :welcome

    def next_action = :home

    def logo_path = "images/macondo/macondo.png"
    def background_path = "images/macondo/bg-img.png"

    def card_attributes = { wide_logo: true }
    def dark_mode_background_path = "images/macondo/bg-img.png"
  end
end
