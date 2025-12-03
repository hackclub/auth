# frozen_string_literal: true

class Components::Backend::Card < Components::Base
  def initialize(title:)
    @title = title
  end

  def view_template
    article class: "card" do
      header class: "card-header" do
        div class: "card-header-left", aria_hidden: true
        h2(class: "card-title") { @title }
        div class: "card-header-right", aria_hidden: true
      end

      section class: "card-body" do
        yield
      end
    end
  end
end
