# frozen_string_literal: true

module SpecialAppCards
  class Blueprint < Base
    def visible?
      identity.ysws_eligible != false && Flipper.enabled?(:blueprint, identity)
    end

    def friendly_name = "Blueprint"

    def tagline = "Design a hardware project, get up to $400 to build it!"

    def icon = "blueprint.png"

    def icon_class = "blueprint-icon"

    def url = "https://blueprint.hackclub.com/?utm_source=HCA"

    def launch_text = "Get Started!"
  end
end
