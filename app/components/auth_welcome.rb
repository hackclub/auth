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
    signup_url = @return_to ? "/signup?return_to=#{CGI.escape(@return_to)}" : "/signup"
    login_url = @return_to ? "/login?return_to=#{CGI.escape(@return_to)}" : "/login"
    
    div(style: "margin: 3rem 0;") do
      div(class: "grid", style: "gap: 1rem;") do
        a(href: signup_url, style: "text-decoration: none;") do
          button(type: "button", class: "primary welcome-create-button") do
            whitespace
            inline_icon("member-add", size: 24)
            whitespace
            plain "Create Account"
          end
        end

        a(href: login_url, style: "text-decoration: none;") do
          button(type: "button", class: "secondary welcome-signin-button") do
            whitespace
            inline_icon("door-enter", size: 24)
            whitespace
            plain "Sign In"
          end
        end
      end
    end
  end

  def render_footer
    footer(class: "welcome-footer") do
      p(class: "welcome-links") do
        a(href: "/faq") { "FAQ" }
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
