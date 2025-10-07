# frozen_string_literal: true

class Components::SSOAppCard < Components::Base
  def initialize(app:)
    @app = app
  end

  def view_template
    form_with(url: idp_initiated_saml_path(slug: @app[:slug]), method: :post, html: { class: "sso-app-card-form", target: "_blank" }) do
      button(type: "submit", class: "sso-app-card") do
        div(class: "card-header") do
          div(class: "app-icon") do
            if @app[:icon].present?
              vite_image_tag("images/sso_apps/#{@app[:icon]}")
            else
              span { @app[:friendly_name][0] }
            end
          end
          
          div(class: "app-info") do
            h3 { @app[:friendly_name] }
            p(class: "app-tagline") { @app[:tagline] }
          end
        end
        
        div(class: "card-footer") do
          span(class: "launch-text") { "Launch →" }
        end
      end
    end
  end
end
