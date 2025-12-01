class ApplicationMailer < ActionMailer::Base
  include Rails.application.routes.url_helpers
  layout "mailer"

  ACCOUNT_FROM = "Hack Club <account@hackclub.com>".freeze
  IDENTITY_FROM = "Hack Club <identity@hackclub.com>".freeze

  before_action :attach_logo

  private

  def attach_logo
    attachments.inline["logo.png"] = Rails.root.join("app/frontend/images/hc-square.png").read
  end

  def env_prefix
    case Rails.env
    when "development" then "[DEV] "
    when "staging" then "[STAGING] "
    else ""
    end
  end

  def prefixed_subject(subject)
    "#{env_prefix}#{subject}"
  end
end
