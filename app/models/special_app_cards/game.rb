# frozen_string_literal: true

module SpecialAppCards
  class Game < Base
    def visible?
      Flipper.enabled?(:game, identity)
    end

    def friendly_name = "Hack Club: The Game"

    def tagline = "Build projects, then compete in a scavenger hunt adventure game across Manhattan"

    def icon = "game.png"

    def url = "https://game.hackclub.com?utm_source=auth-card"

    def launch_text = "Play Now!"
  end
end
