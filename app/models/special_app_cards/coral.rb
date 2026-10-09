# frozen_string_literal: true

module SpecialAppCards
  class Coral < Base
    def visible?
      identity.ysws_eligible != false && Flipper.enabled?(:app_card_coral_2026_10_08, identity)
    end

    def friendly_name = "Coral"

    def tagline = "Spend 40 hours building and to join us in Australia"

    def icon = "coral.png"

    def url = "https://coral.hackclub.com"

    def launch_text = "start shippin'"
  end
end
