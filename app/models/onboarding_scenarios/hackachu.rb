# frozen_string_literal: true

module OnboardingScenarios
  class Hackachu < Base
    def self.slug = "hackachu"

    def title = "Welcome to Hackachu!"

    def form_fields = [ :first_name, :last_name, :primary_email, :birthday, :country ]

    def slack_user_type = :full_member

    def slack_channels = chans(:hackachu, :hackachu_announcements, :hackachu_help, :welcome_to_hack_club, :help)

    def slack_onboarding_flow = :internal_tutorial

    def next_action = :home

    def logo_path = "images/hackachu/hackachu.png"
    def background_path = "images/hackachu/hackachubanner.png"

    def card_attributes = { wide_logo: true }
    def dark_mode_background_path = "images/hackachu/hackachubanner.png"
  end
end