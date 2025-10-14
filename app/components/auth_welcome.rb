class Components::AuthWelcome < Components::Base
  def initialize(service_name: nil, return_to: nil)
    @service_name = service_name
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
      if @service_name.present?
        h1 { "Continue to #{@service_name}" }
        small { "Sign in or create an account to continue" }
      else
        h1 { "Continue" }
        small { "Sign in or create an account to continue" }
      end
    end
  end

  def render_actions
    div(style: "margin: 3rem 0;") do
      div(class: "grid", style: "gap: 1rem;") do
        a(href: helpers.signup_path(return_to: @return_to), style: "text-decoration: none;") do
          button(type: "button", class: "primary welcome-create-button") do
            plain "Create Account"
          end
        end

        a(href: helpers.login_path(return_to: @return_to), style: "text-decoration: none;") do
          button(type: "button", class: "secondary welcome-signin-button") do
            plain "Sign In"
          end
        end
      end
    end
  end

  def render_footer
    footer(class: "welcome-footer") do
      p(class: "welcome-links") do
        a(href: helpers.faq_path) { "FAQ" }
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
            plain " from #{distance_of_time_in_words(Rails.application.config.server_start_time, Time.current)} ago"
          end
        end
      end
    end
  end
end
