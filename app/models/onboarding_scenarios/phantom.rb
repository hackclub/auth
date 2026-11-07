# frozen_string_literal: true

module OnboardingScenarios
  class Phantom < Base
    def self.slug = "Phantom"

    def title = "Welcome to PHANTOM"

    def form_fields = [ :first_name, :last_name, :primary_email, :birthday, :country ]

    def slack_user_type = :full_member

    def slack_channels = chans(:phantom, :phantom_bulletin, :phantom_help, :welcome_to_hack_club, :help)

    def slack_onboarding_flow = :internal_tutorial

    def next_action = :home

    def logo_path = "images/phantom/phantom_hc_logo.png"
    def background_path = "images/phantom/bg.png"

    def card_attributes = { wide_logo: true }
    def dark_mode_background_path = "images/phantom/bg.png"
  end
end
