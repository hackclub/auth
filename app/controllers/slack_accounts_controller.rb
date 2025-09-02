class SlackAccountsController < ApplicationController
  before_action :authenticate_identity!

  def new
    redirect_uri = url_for(action: :create, only_path: false)
    Rails.logger.info "Starting Slack OAuth flow for account linking with redirect URI: #{redirect_uri}"
    redirect_to Identity.slack_authorize_url(redirect_uri),
                host: "https://slack.com",
                allow_other_host: true
  end

  def create
    redirect_uri = url_for(action: :create, only_path: false)

    if params[:error].present?
      Rails.logger.error "Slack OAuth error: #{params[:error]}"
      uuid = Honeybadger.notify("Slack OAuth error: #{params[:error]}")
      redirect_to root_path, alert: "failed to link Slack account! (error: #{uuid})"
      return
    end

    begin
      result = Identity.link_slack_account(params[:code], redirect_uri, current_identity)

      if result[:success]
        Rails.logger.info "Successfully linked Slack account #{result[:slack_id]} to Identity #{current_identity.id}"
        redirect_to root_path, notice: "Successfully linked your Slack account!"
      else
        redirect_to root_path, alert: result[:error]
      end
    rescue => e
      Rails.logger.error "Error linking Slack account: #{e.message}"
      uuid = Honeybadger.notify(e)
      redirect_to root_path, alert: "error linking Slack account! (error: #{uuid})"
    end
  end
end
