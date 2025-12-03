# frozen_string_literal: true

class Components::Backend::Item < Components::Base
  extend Literal::Properties

  prop :icon, _String?
  prop :href, _String?
  prop :onclick, _String?
  prop :target, _String?

  def view_template
    if @href
      a class: "item", href: @href, target: @target, onclick: (safe(@onclick) if @onclick) do
        render_icon
        render_text { yield }
      end
    else
      button class: "item", type: "button", onclick: (safe(@onclick) if @onclick) do
        render_icon
        render_text { yield }
      end
    end
  end

  private

  def render_icon
    figure(class: "icon") { @icon || "·" }
  end

  def render_text
    span(class: "text") { yield }
  end
end
