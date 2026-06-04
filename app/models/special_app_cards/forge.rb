# frozen_string_literal: true
module SpecialAppCards
  class Forge < Base
    def visible?
      identity.ysws_eligible != false
    end
    def friendly_name = "Forge"
    def tagline = "This is program where teens like yourself can design and build hardware projects, and get them funded!"
    def icon = "Forge.png"
    def icon_background = "#1c1b1b"
    def url = "https://forge.hackclub.com/"
    def launch_text = "Get forging now"
  end
end
