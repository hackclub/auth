class Slack::NotifyGuardiansJob < ApplicationJob
  queue_as :default
  include Rails.application.routes.url_helpers

  PING_LINE = "hey <!subteam^S07TQBKCVL7>!"

  def slack_escape(text) = text.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")

  def perform(identity, without_ping: false)
    verf = identity.latest_verification
    return unless verf

    reason_line = if identity.verification_status == "ineligible"
                    "their ID had the following issue: #{slack_escape(identity.verification_status_reason)} – #{slack_escape(identity.verification_status_reason_details || "(unspecified)")}"
    else
                    "nothing was wrong with their ID, they're just >18 years old."
    end
    slack_id = identity.slack_id || SlackService.find_by_email(identity.primary_email)
    slack_id_line = if slack_id.present?
                      "<@#{slack_id}> (#{slack_id})"
    else
                      "unknown...?"
    end
    message = <<~EOM.strip
      #{PING_LINE unless without_ping}
      there's someone that needs to be deactivated:
      *name*: #{slack_escape(identity.first_name)} #{slack_escape(identity.last_name)}
      *email*: #{slack_escape(identity.primary_email)}
      *slack*: #{slack_id_line}
      #{reason_line}
      thanks!
    EOM

    context_line = "*ref:* <#{backend_identity_url(identity)}|#{identity.public_id}> / <#{backend_verification_url(verf)}|#{verf.public_id}>"
    HTTP.post(ENV["SLACK_ADULT_WEBHOOK_URL"], body: {
      "blocks": [
        {
          "type": "section",
          "text": {
            "type": "mrkdwn",
            "text": message
          }
        },
        {
          "type": "context",
          "elements": [
            {
              "type": "mrkdwn",
              "text": context_line
            }
          ]
        }
      ]
    }.to_json)
  end
end
