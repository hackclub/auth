# frozen_string_literal: true

module SpecialAppCards
  class Stardance < Base
    def visible?
      identity.ysws_eligible != false && Flipper.enabled?(:stardance, identity)
    end

    def friendly_name = "Stardance"

    def tagline = "it's outta this world!"

    def icon = "stardance.png"

    def url = "https://stardance.hackclub.com"

    def launch_text = "blast off!"
  end
end
