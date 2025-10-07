# frozen_string_literal: true

class Components::SSOAppGrid < Components::Base
  def initialize(apps:)
    @apps = apps
  end

  def view_template
    div(class: "sso-app-grid") do
      h2 { "Your Applications" }
      
      if @apps.any?
        div(class: "grid") do
          @apps.each do |app|
            render Components::SSOAppCard.new(app: app)
          end
        end
      else
        p(class: "no-apps") { "No applications available" }
      end
    end
  end
end
