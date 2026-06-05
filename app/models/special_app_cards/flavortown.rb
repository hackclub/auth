# frozen_string_literal: true

module SpecialAppCards
  class Flavortown < Base
    def visible?
      identity.ysws_eligible != false && Flipper.enabled?(:app_card_flavortown_2025_12_09, identity)
    end

    def friendly_name = "Flavortown"

    def tagline = "anyone can cook!"

    def icon = "flavortown.png"

    def url = "https://flavortown.hackclub.com"

    def launch_text = "to the kitchen!"
  end
end
