# frozen_string_literal: true

module OnboardingScenarios
  class Campfire < Base
    def self.slug = "campfire"

    def title = "Welcome to Campfire"

    def form_fields
      [ :first_name, :last_name, :primary_email, :birthday, :country ]
    end

    def slack_user_type = :multi_channel_guest

    def slack_channels = chans(:campfire_flagship, :campfire_flagship_bulletin, :campfire_flagship_help, :welcome_to_hack_club)

    def slack_onboarding_flow = :internal_tutorial

    def next_action = :home

    def logo_path = "images/campfire/cf-logo.png"
    def background_path = "images/campfire/campfire.png"

    def card_attributes = { wide_logo: true }
    def dark_mode_background_path = "images/campfire/campfire.png"

    def dialogue_flow
      {
        intro: { template: "tutorial/campfire/intro", next: :welcome },
        welcome: { template: "tutorial/03_welcome", next: nil }
      }
    end
  end
end