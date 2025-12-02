# frozen_string_literal: true

class Components::Backend::Card < Components::Base
  def initialize(title:, mode: nil)
    @title = title
    @mode = mode
  end

  def view_template
    article class: "card" do
      header class: "action" do
        div class: @mode == :left ? "leftCorner" : "left", aria_hidden: true
        h2(class: "title") { @title }
        div class: @mode == :left ? "rightCorner" : "right", aria_hidden: true
      end

      section class: "children" do
        yield
      end
    end
  end
end
