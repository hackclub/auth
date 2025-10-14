class Slack::InteractivityController < ActionController::API
  before_action :verify_slack_request
  before_action :set_current_identity

  attr_reader :current_identity

  def create
    payload = JSON.parse(params[:payload])

    case payload["type"]
    when "block_actions"
      handle_block_actions(payload)
    else
      head :ok
    end
  end

  private

  def handle_block_actions(payload)
    action = payload.dig("actions", 0)
    return head :ok unless action

    action_id = action["action_id"]

    case action_id
    when "coc_continue"
      Tutorial::CocContinueJob.perform_later(current_identity)
    when "tutorial_agree"
      Tutorial::AgreeJob.perform_later(current_identity)
    end

    head :ok
  end

  def set_current_identity
    payload = JSON.parse(params[:payload])
    slack_id = payload.dig("user", "id")

    @current_identity = Identity.find_by(slack_id: slack_id)

    unless @current_identity
      Rails.logger.warn "Slack interactivity from unknown user: #{slack_id}"
      head :unauthorized
      nil
    end
  end

  def verify_slack_request
    timestamp = request.headers["X-Slack-Request-Timestamp"]
    signature = request.headers["X-Slack-Signature"]

    return head :unauthorized unless timestamp && signature

    if (Time.now.to_i - timestamp.to_i).abs > 60 * 5
      return head :unauthorized
    end

    signing_secret = ENV["SLACK_SIGNING_SECRET"]
    return head :unauthorized unless signing_secret

    sig_basestring = "v0:#{timestamp}:#{request.raw_post}"
    my_signature = "v0=" + OpenSSL::HMAC.hexdigest("SHA256", signing_secret, sig_basestring)

    unless ActiveSupport::SecurityUtils.secure_compare(my_signature, signature)
      head :unauthorized
    end
  end
end
