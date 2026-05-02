# frozen_string_literal: true

module SpecialAppCards
  class Macondo < Base
    def visible?
      identity.ysws_eligible != false && Flipper.enabled?(:macondo, identity)
    end

    def friendly_name = "Macondo"

    def tagline = "Build personal hardware or software projects, get them funded, fly to a hackathon in Bogotá."

    def icon = "macondo.png"

    def url = "https://macondo.hackclub.com/?utm_source=HCA"

    def launch_text = "Get Started!"
  end
end
