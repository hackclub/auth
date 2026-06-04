class Slack::NotifyReviewQueueJob < ApplicationJob
  queue_as :default
  include Rails.application.routes.url_helpers

  def perform(verification)
    return unless ENV["SLACK_REVIEW_WEBHOOK_URL"].present?

    identity = verification.identity
    issues = verification.issues || []

    message = <<~EOM.strip
      new verification held for review:
      *name*: #{identity.first_name} #{identity.last_name}
      *email*: #{identity.primary_email}
      *flags*: #{issues.any? ? issues.join(", ") : "none listed"}
    EOM

    HTTP.post(ENV["SLACK_REVIEW_WEBHOOK_URL"], body: {
      blocks: [
        { type: "section", text: { type: "mrkdwn", text: message } },
        { type: "context", elements: [ { type: "mrkdwn", text: "<#{backend_verification_url(verification)}|review in backend>" } ] }
      ]
    }.to_json)
  end
end
