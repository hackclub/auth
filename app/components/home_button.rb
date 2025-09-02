# frozen_string_literal: true

class Components::HomeButton < Components::Base
  def view_template
    a href: root_path do
      "← back to home"
    end
  end
end
