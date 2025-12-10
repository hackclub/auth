# frozen_string_literal: true

class Components::SSOAppGrid < Components::Base
  def initialize(apps:, special_apps: [])
    @apps = apps
    @special_apps = special_apps
  end

  def view_template
    div(class: "sso-app-grid") do
      h2 { t "home.apps.heading" }

      all_apps = @apps + @special_apps.map(&:to_h)

      if all_apps.any?
        div(class: "grid") do
          all_apps.each do |app|
            render Components::AppCard.new(app: app)
          end
        end
      else
        p(class: "no-apps") { t "home.apps.none" }
      end
    end
  end
end
