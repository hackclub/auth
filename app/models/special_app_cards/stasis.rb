# frozen_string_literal: true

module SpecialAppCards
  class Stasis < Base
    def visible?
      identity.ysws_eligible != false && Flipper.enabled?(:stasis, identity)
    end

    def friendly_name = "Stasis"

    def tagline = "Build hardware projects, get up to $300, fly to a hackathon in Texas"

    def icon = "stasis.png"

    def icon_background = "#0E305B"

    def url = "https://stasis.hackclub.com/?utm_source=HCA"

    def launch_text = "Get Started!"
  end
end
