# frozen_string_literal: true

module SpecialAppCards
  class Crescent < Base
    def visible?
      identity.ysws_eligible != false && Flipper.enabled?(:app_card_crescent_2026_09_23, identity)
    end

    def friendly_name = "Crescent"

    def tagline = "Four different challenges each week - pick a card, then ship something!"

    def icon = "crescent.png"

    def url = "https://crescent.hackclub.com/?utm_source=hca"

    def launch_text = "onwards!"
  end
end
