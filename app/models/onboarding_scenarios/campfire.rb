# frozen_string_literal: true

module OnboardingScenarios
  class Campfire < Base
    def self.slug = "campfire"

    def title = "Welcome to Campfire"

    def form_fields
      [ :first_name, :last_name, :primary_email, :birthday, :country ]
    end

    def slack_user_type = :multi_channel_guest

    def next_action = :home

    def logo_path = "images/campfire/cf-logo.png"
    def logo_class = "campfire-logo"
    def background_path = "images/campfire/campfire.png"
    def dark_mode_background_path = "images/campfire/campfire.png"
  end
end
