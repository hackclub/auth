# frozen_string_literal: true

# Manimator (manimator.hackclub.com): make math videos with manim in the browser. Its onboarding story ends at a
# portal to Hack Club that π holds open, so this side carries the same world on: π's logo, a manim frame with the
# portal's rings of π's digits round the card, π's words, and π greeting you in Slack.
module OnboardingScenarios
  class Manimator < Base
    def self.slug = "manimator"

    def title = "almost through the portal"

    def welcome_headline = "You made it through the portal"
    def welcome_subtitle = "Type your email and Hack Club sends you a 6-digit code. Then you're straight back with π."

    def form_fields = [ :first_name, :last_name, :primary_email, :birthday, :country ]

    def slack_user_type = :full_member

    def slack_channels = chans(:manimator, :help, :identity_help, :welcome_to_hack_club, :slack_guide) + promotion_channels

    def promotion_channels = chans(:manimator, :library, :lounge, :welcome, :happenings, :community_announcements, :announcements, :ysws)

    def first_step = :welcome

    def bot_name = "π"
    def bot_icon_url = "https://manimator.hackclub.com/pi.png"

    def logo_path = "images/manimator/pi.png"
    def background_path = "images/manimator/bg.webp"
  end
end
