# frozen_string_literal: true

module SpecialAppCards
  class Stasis < Base
    def visible?
      identity.ysws_eligible != false && Flipper.enabled?(:stasis, identity)
    end

    def friendly_name = "Stasis"

    def tagline = "Design a hardware project, get up to $300 to build it!"

    def icon = "stasis.png"

    def icon_background = "#DAD2BF"

    def url = "https://stasis.hackclub.com/?utm_source=HCA"

    def launch_text = "Get Started!"
  end
end
