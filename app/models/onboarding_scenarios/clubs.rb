module OnboardingScenarios
  class Clubs < Base
    def self.slug = "clubs"

    def title = "Ready to start leading your Club?"

    def form_fields = [ :first_name, :last_name, :primary_email, :birthday, :country ]

    def slack_user_type = :full_member

    def slack_channels = chans(:leaders, :leaders_bulletin, :identity_help, :help, :welcome_to_hack_club, :slack_guide) + promotion_channels

    def promotion_channels = chans(:library, :lounge, :welcome, :happenings, :community, :announcements)

    def first_step = :welcome

    def logo_path = "images/clubs/icon.png"
  end
end
