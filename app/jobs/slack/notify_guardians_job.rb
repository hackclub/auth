class Slack::NotifyGuardiansJob < ApplicationJob
  queue_as :default
  include Rails.application.routes.url_helpers

  PING_LINE = "hey <!subteam^S07TQBKCVL7>!"

  def perform(identity, without_ping: false)
    reason_line = if identity.verification_status == "ineligible"
                    "their ID had the following issue: #{identity.verification_status_reason} – #{identity.verification_status_reason_details || "(unspecified)"}"
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
      *name*: #{identity.first_name} #{identity.last_name}
      *email*: #{identity.primary_email}
      *slack*: #{slack_id_line}
      #{reason_line}
      thanks!
    EOM

    verf = identity.latest_verification

    context_line = "*ref:* <#{backend_identity_url(identity)}|#{identity.public_id}> / <#{backend_verification_url(verf)}|#{verf.public_id}>"
    HTTP.post(Rails.application.credentials.slack.adult_webhook, body: {
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
