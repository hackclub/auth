# frozen_string_literal: true

class Components::Backend::ActionButton < Components::Base
  extend Literal::Properties

  prop :hotkey, _String?
  prop :onclick, _String?
  prop :selected, _Boolean?
  prop :type, _String?, default: "button"

  def view_template
    button class: "action_button#{" selected" if @selected}", type: @type, onclick: (safe(@onclick) if @onclick) do
      span(class: "hotkey") { @hotkey } if @hotkey.present?
      plain yield
    end
  end
end
