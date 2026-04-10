# frozen_string_literal: true

module SpecialAppCards
  class Beest < Base
    def visible?
      identity.ysws_eligible != false && Flipper.enabled?(:beest, identity)
    end

    def friendly_name = "Beest"

    def tagline = "Design a hardware project, get up to $400 to build it!"

    def icon = "Beest.png"

    def icon_background = "#0E305B"

    def url = "https://beest.hackclub.com/?utm_source=HCA"

    def launch_text = "Start Building!"
  end
end
