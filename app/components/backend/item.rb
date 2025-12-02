# frozen_string_literal: true

class Components::Backend::Item < Components::Base
  extend Literal::Properties

  prop :icon, _String?
  prop :href, _String?
  prop :onclick, _String?
  prop :target, _String?

  def view_template
    if @href
      a class: "item", href: @href, target: @target, tab_index: nil, role: :link do
        icon
        children { yield }
      end
    else
      div class: "item", onclick: (safe(@onclick) if @onclick), tab_index: nil, role: :button do
        icon
        children { yield }
      end
    end
  end

  def icon = figure(class: "icon") { @icon }

  def children(&block) = span(class: "text") { yield }
end
