module OnboardingScenarios
  class Fallout < Base
    def self.slug = "fallout"

    def title = "let's build!"

    def form_fields
      [ :first_name, :last_name, :primary_email, :birthday, :country ]
    end

    def slack_user_type = :multi_channel_guest

    def slack_channels = chans(:fallout, :fallout_help, :fallout_bulletin, :identity_help)

    def next_action = :home

    def logo_path = "images/fallout/fallout.png"
    def background_path = "images/fallout/bg-img.png"

    def card_attributes = { wide_logo: true }
    def dark_mode_background_path = "images/fallout/bg-img.png"
  end
end
