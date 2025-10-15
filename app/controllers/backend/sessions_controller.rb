module Backend
  class SessionsController < ApplicationController
    skip_before_action :authenticate_user!, only: [ :new, :create, :fake_slack_callback_for_dev ]

    skip_after_action :verify_authorized

    def new
      redirect_uri = url_for(action: :create, only_path: false)
      redirect_to User.authorize_url(redirect_uri),
                  host: "https://slack.com",
                  allow_other_host: true
    end

    def create
      redirect_uri = url_for(action: :create, only_path: false)

      if params[:error].present?
        uuid = Honeybadger.notify("Slack OAuth error: #{params[:error]}")
        redirect_to backend_login_path, alert: "failed to authenticate with Slack! (error: #{uuid})"
        return
      end

      begin
        @user = User.from_slack_token(params[:code], redirect_uri)
      rescue => e
        uuid = Honeybadger.notify(e)
        redirect_to backend_login_path, alert: "error authenticating! (error: #{uuid})"
        return
      end

      if @user&.persisted?
        session[:user_id] = @user.id
        flash[:success] = "welcome aboard!"
        redirect_to backend_root_path
      else
        redirect_to backend_login_path, alert: "you haven't been provisioned an account on this service yet – this attempt been logged."
      end
    end

    def fake_slack_callback_for_dev
      unless Rails.env.development?
        Honeybadger.notify("Fake Slack callback attempted in non-development environment. WTF?!")
        redirect_to backend_root_path, alert: "this is only available in development mode."
        return
      end

      @user = User.find_by(slack_id: params[:slack_id], active: true)
      if @user.nil?
        redirect_to backend_root_path, alert: "dunno who that is, sorry."
        return
      end

      session[:user_id] = @user.id
      redirect_to backend_root_path, notice: "welcome aboard!"
    end

    def destroy
      session[:user_id] = nil
      redirect_to backend_root_path, notice: "bye, see you next time!"
    end
  end
end
