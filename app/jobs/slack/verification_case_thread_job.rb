# every case gets one slack thread; updates land as replies so the
# whole story reads top to bottom in one place.
class Slack::VerificationCaseThreadJob < ApplicationJob
  queue_as :default
  include Rails.application.routes.url_helpers

  def perform(verification_case, text)
    channel = ENV["SLACK_MANUAL_VERIFICATION_CHANNEL_ID"]
    return if channel.blank?

    if verification_case.slack_thread_ts.present?
      SlackService.client.chat_postMessage(
        channel: verification_case.slack_channel_id,
        thread_ts: verification_case.slack_thread_ts,
        text: text
      )
    else
      response = SlackService.client.chat_postMessage(
        channel: channel,
        text: "manual verification case `#{verification_case.public_id}` — #{text}\n<#{backend_verification_case_url(verification_case)}|view in backend>"
      )
      verification_case.update!(
        slack_channel_id: response["channel"],
        slack_thread_ts: response["ts"]
      )
    end
  rescue Slack::Web::Api::Errors::SlackError => e
    Sentry.capture_exception(e, tags: { component: "slack" }, extra: { case_id: verification_case.id })
  end
end
