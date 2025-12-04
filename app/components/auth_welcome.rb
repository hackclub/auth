class Components::AuthWelcome < Components::Base
  include Phlex::Rails::Helpers::DistanceOfTimeInWordsToNow

  def initialize(headline:, subtitle:, return_to: nil)
    @headline = headline
    @subtitle = subtitle
    @return_to = return_to
  end

  def view_template
    div(class: "auth-container") do
      div(class: "auth-card") do
        render_header
        render_actions
        render_footer
      end
    end
  end

  private

  def render_header
    header do
      h1 { @headline }
      small { @subtitle }
    end
  end

  def render_actions
    login_url = @return_to ? "/login?return_to=#{CGI.escape(@return_to)}" : "/login"

    div(style: "margin: 3rem 0;") do
      form(
        action: login_url,
        method: "post"
      ) do
        input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)

        div(style: "margin-bottom: 1rem;") do
          input(
            type: "email",
            name: "email",
            placeholder: t("identities.email_placeholder"),
            required: true,
            autocomplete: "email",
            style: "width: 100%;"
          )

          small(style: "color: var(--muted-color); display: block; margin-top: 0.5rem;") do
            plain helpers.t("logins.welcome.email_help")
          end
        end

        button(
          type: "submit",
          class: "primary",
          style: "width: 100%; margin-top: 1rem;"
        ) do
          plain helpers.t("logins.welcome.continue")
          whitespace
          plain "→"
        end
      end
    end
  end

  def render_footer
    footer(class: "welcome-footer") do
      p do
        plain helpers.t("logins.welcome.trouble_help")
        a(href: "mailto:auth@hackclub.com") { "auth@hackclub.com" }
        plain "."
      end

      p(class: "welcome-links") do
        a(href: "/docs/privacy") { "Privacy" }
        plain " • "
        a(href: "/docs/terms-of-service") { "Terms" }
        plain " • "
        a(href: "/docs/contact") { "Contact" }
      end

      if Rails.application.config.try(:git_version).present?
        span(class: "welcome-version") do
          plain "Build "
          if Rails.application.config.try(:commit_link).present?
            a(href: Rails.application.config.commit_link, target: "_blank") do
              Rails.application.config.git_version
            end
          else
            plain Rails.application.config.git_version
          end
          if Rails.application.config.try(:server_start_time).present?
            plain " from #{distance_of_time_in_words_to_now(Rails.application.config.server_start_time)} ago"
          end
        end
      end
    end
  end
end
