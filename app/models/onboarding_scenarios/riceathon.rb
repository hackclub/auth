module OnboardingScenarios
  class Riceathon < Base
    def self.slug = "riceathon"

    def title = "ready to start ricing?"

    def form_fields
      [ :first_name, :last_name, :primary_email, :birthday, :country ]
    end

    def slack_user_type = :multi_channel_guest

    def slack_channels = chans(:riceathon, :announcements, :welcome_to_hack_club, :identity_help)

    def promotion_channels = chans(:riceathon, :announcements, :welcome_to_hack_club, :identity_help)

    def next_action = :slack

    def use_dm_channel? = false

    def promote_on_verification = true

    def logo_path = "images/riceathon/RiceathonGlow.png"

    def card_attributes = { wide_logo: true }

    # When user is promoted via verification approval, send them the welcome message
    # ensures theysee the CoC
    def after_verification_promotion(identity)
      RalseiEngine.send_step(identity, :welcome)
    end
  end
end
