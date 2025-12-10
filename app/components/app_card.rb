# frozen_string_literal: true

class Components::AppCard < Components::Base
  def initialize(app:)
    @app = app
  end

  def view_template
    if @app[:special]
      render_link_card
    else
      render_saml_card
    end
  end

  private

  def render_saml_card
    form_with(url: idp_initiated_saml_path(slug: @app[:slug]), method: :post, html: { class: "sso-app-card-form", target: "_blank" }) do
      button(type: "submit", class: "sso-app-card secondary") do
        render_card_content(launch_text: t("home.apps.launch"))
      end
    end
  end

  def render_link_card
    div(class: "sso-app-card-form") do
      a(href: @app[:url], class: "sso-app-card secondary", target: "_blank") do
        render_card_content(launch_text: @app[:launch_text] || t("home.apps.launch"))
      end
    end
  end

  def render_card_content(launch_text:)
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
      span(class: "launch-text") do
        plain launch_text
        inline_icon "external", size: 24
      end
    end
  end
end
