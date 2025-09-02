class ApplicationMailer < ActionMailer::Base
  default from: "identity@hackclub.com"
  layout "mailer"

  def send_it!
    mail(to: @recipient, template_path: "mailers", template_name: "blank_mailer")
  end
end
