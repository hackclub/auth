# frozen_string_literal: true

class Components::SSOAppGrid < Components::Base
  def initialize(apps:)
    @apps = apps
  end

  def view_template
    div(class: "sso-app-grid") do
      h2 { t "home.apps.heading" }

      if @apps.any?
        div(class: "grid") do
          @apps.each do |app|
            render Components::SSOAppCard.new(app: app)
          end
        end
      else
        p(class: "no-apps") { t "home.apps.none" }
      end
    end
  end
end
