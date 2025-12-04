class Components::Footer < Components::Base
  include Phlex::Rails::Helpers::TimeAgoInWords

  def view_template
    footer(class: "app-footer") do
      div(class: "footer-content") do
        div(class: "footer-main") do
          p(class: "app-name") { "Identity Vault" }
          p(class: "footer-links") do
            a(href: "/docs/privacy") { "Privacy" }
            plain " • "
            a(href: "/docs/terms-of-service") { "Terms" }
            plain " • "
            a(href: "/docs/contact") { "Contact" }
          end
        end

        div(class: "footer-version") do
          div(class: "version-info") do
            p do
              plain "Build "
              if git_version.present?
                if commit_link.present?
                  a(href: commit_link, target: "_blank", class: "version-link") do
                    "v#{git_version}"
                  end
                else
                  span(class: "version-text") { "v#{git_version}" }
                end
              end
              plain " from #{time_ago_in_words(server_start_time)} ago"
            end
          end
        end

        div(class: "environment-badge #{Rails.env.downcase}") do
          Rails.env.upcase
        end
      end
    end
  end

  def git_version = Rails.application.config.try(:git_version)

  def commit_link = Rails.application.config.try(:commit_link)

  def server_start_time
    Rails.application.config.try(:server_start_time)
  end
end
