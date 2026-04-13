# frozen_string_literal: true

module OnboardingScenarios
  class Fallout < Base
    def self.slug = "fallout"

    def title = "let's build!"

    def form_fields
      [ :first_name, :last_name, :primary_email, :birthday, :country ]
    end

    def slack_channels = chans(:fallout, :fallout_help, :fallout_bulletin, :identity_help)

    def slack_onboarding_flow = :internal_tutorial

    def next_action = :home

    def logo_path = "images/fallout/fallout.png"
    def background_path = "images/fallout/bg-img.png"

    def card_attributes = { wide_logo: true }
    def dark_mode_background_path = "images/fallout/bg-img.png"

    def dialogue_flow
      {
        intro: { template: "tutorial/fallout/intro", next: :welcome },
        welcome: { template: "tutorial/fallout/03_welcome", next: nil }
      }
    end
  end
end
