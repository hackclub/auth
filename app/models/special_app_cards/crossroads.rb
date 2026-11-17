# frozen_string_literal: true

module SpecialAppCards
  class Crossroads < Base
    def visible?
      identity.ysws_eligible != false && Flipper.enabled?(:app_card_crossroads_2026_11_17, identity)
    end

    def friendly_name = "Crossroads"

    def tagline = "Build projects, hack across Europe by train!"

    def icon = "crossroads.gif"

    def url = "https://crossroads.hackclub.com/?utm_source=auth"

    def launch_text = "All aboard!"
  end
end
