# frozen_string_literal: true

module SpecialAppCards
  class Phantom < Base
    def visible?
      identity.ysws_eligible != false && Flipper.enabled?(:app_card_phantom_2026_11_06, identity)
    end

    def friendly_name = "Phantom"

    def tagline = "Build projects, go to an escape room hackathon in Philadelphia."

    def icon = "phantom.png"

    def url = "https://phantom.hackclub.com/?utm_source=hca"

    def launch_text = "let's go!"
  end
end
