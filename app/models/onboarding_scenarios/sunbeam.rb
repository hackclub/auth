# frozen_string_literal: true

module OnboardingScenarios
  class Sunbeam < Base
    def self.slug = "sunbeam"

    def title = "Welcome to Sunbeam!"

    def form_fields = [ :first_name, :last_name, :primary_email, :birthday, :country ]

    def slack_user_type = :full_member

    def slack_channels = chans(:sunbeam, :sunbeam_announcements, :sunbeam_help, :welcome_to_hack_club, :help)

    def slack_onboarding_flow = :internal_tutorial

    def next_action = :home

    def logo_path = "images/sunbeam/sunbeam.png"
    def background_path = "images/sunbeam/sunbeambanner.png"

    def card_attributes = { wide_logo: true }
    def dark_mode_background_path = "images/sunbeam/sunbeambanner.png"
  end
end
