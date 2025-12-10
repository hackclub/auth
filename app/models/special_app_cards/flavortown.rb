# frozen_string_literal: true

module SpecialAppCards
  class Flavortown < Base
    def visible?
      identity.ysws_eligible != false && Flipper.enabled?(:flavortown, identity)
    end

    def friendly_name = "Flavortown"

    def tagline = "Anyone can cook!"

    def icon = "flavortown.png"

    def url = "https://flavortown.hackclub.com"

    def launch_text = "to the kitchen!"
  end
end
