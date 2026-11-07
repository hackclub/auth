# frozen_string_literal: true

module SpecialAppCards
  class Hacktank < Base
    def visible?
      identity.ysws_eligible != false && Flipper.enabled?(:app_card_hacktank_2026_10_08, identity)
    end

    def friendly_name = "Hacktank"

    def tagline = "Make a real product, go viral, pitch to VCs in San Francisco"

    def icon = "hacktank.jpg"

    def url = "https://hacktank.hackclub.com"

    def launch_text = "start building"
  end
end
