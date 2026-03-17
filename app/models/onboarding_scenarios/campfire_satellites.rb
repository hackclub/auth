# frozen_string_literal: true

module OnboardingScenarios
  class CampfireSatellites < Base
    def self.slug = "campfire-satellites"

    def title = "Join us around the Campfire"

    def form_fields
      [ :first_name, :last_name, :primary_email, :birthday, :country ]
    end

    def slack_user_type = :multi_channel_guest

    def slack_channels = chans(:campfire, :campfire_bulletin, :campfire_help, :welcome_to_hack_club, :identity_help)

    def slack_onboarding_flow = :internal_tutorial

    def next_action = :slack

    def logo_path = "images/campfire-satellites/cf-logo.png"
    def background_path = "images/campfire-satellites/campfire.png"

    def card_attributes = { wide_logo: true }
    def dark_mode_background_path = "images/campfire-satellites/campfire.png"
  end
end
