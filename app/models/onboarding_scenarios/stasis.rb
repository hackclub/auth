module OnboardingScenarios
  class Stasis < Base
    def self.slug = "stasis"

    def title = "ready to start building?"

    def form_fields
      [ :first_name, :last_name, :primary_email, :birthday, :country ]
    end

    def slack_user_type = :multi_channel_guest

    def slack_channels = chans(:stasis, :stasis_support, :stasis_bulletin, :identity_help)

    def next_action = :home

    def logo_path = "images/stasis/stasis.png"
    def background_path = "images/stasis/bg-img.png"

    def card_attributes = { wide_logo: true }
    def dark_mode_background_path = "images/stasis/bg-img.png"
  end
end
