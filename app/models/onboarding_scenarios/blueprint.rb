module OnboardingScenarios
  class Blueprint < Base
    def self.slug = "blueprint"

    def title = "ready to start building?"

    def form_fields
      [ :first_name, :last_name, :primary_email, :birthday, :country ]
    end

    def slack_user_type = :multi_channel_guest

    def slack_channels = chans(:blueprint, :blueprint_support, :blueprint_announcements, :identity_help)

    def next_action = :home

    def logo_path = "images/blueprint/blueprint.png"
    def background_path = "images/blueprint/bg-img.png"

    def card_attributes = { wide_logo: true }
    def dark_mode_background_path = "images/blueprint/bg-img.png"
  end
end
