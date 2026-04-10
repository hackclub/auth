# frozen_string_literal: true

module SpecialAppCards
  class Beest < Base
    def visible?
      identity.ysws_eligible != false && Flipper.enabled?(:beest_2026_04_10, identity)
    end

    def friendly_name = "Beest"

    def tagline = "Build to earn a ticket to a week long hackathon in the Netherlands!"

    def icon = "Beest.png"

    def icon_background = "#0E305B"

    def url = "https://beest.hackclub.com/?utm_source=HCA"

    def launch_text = "Start Building!"
  end
end
