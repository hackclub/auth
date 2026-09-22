# frozen_string_literal: true

module SpecialAppCards
  class Forge < Base
    def visible?
      identity.ysws_eligible != false && Flipper.enabled?(:app_card_forge_2026_09_19, identity)
    end

    def friendly_name = "Forge"

    def tagline = "Build hardware, get funding!"

    def icon = "forge.png"

    def url = "https://forge.hackclub.com"

    def launch_text = "Start building!"
  end
end
