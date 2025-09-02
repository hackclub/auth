module Backend
  class ApplicationController < ActionController::Base
    include PublicActivity::StoreController
    include Pundit::Authorization

    layout "backend"

    after_action :verify_authorized

    helper_method :current_user, :user_signed_in?

    before_action :authenticate_user!, :set_honeybadger_context

    before_action :set_paper_trail_whodunnit

    def current_user
      @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
    end

    def current_impersonator
      @current_impersonator ||= User.find_by(id: session[:impersonator_user_id]) if session[:impersonator_user_id]
    end

    alias_method :find_current_auditor, :current_user
    alias_method :user_for_public_activity, :current_user

    def user_for_paper_trail = current_impersonator&.id || current_user&.id
    def info_for_paper_trail = { extra_data: { ip: request.remote_ip, user_agent: request.user_agent, impersonating: !!current_impersonator, pretending_to_be: current_impersonator && current_user }.compact_blank }

    def user_signed_in? = !!current_user

    def authenticate_user!
      unless user_signed_in?
        return redirect_to backend_login_path, alert: ("you need to be logged in!")
      end
      unless @current_user&.active?
        session[:user_id] = nil
        @current_user = nil
        redirect_to backend_login_path, alert: ("you need to be logged in!")
      end
    end

    def set_honeybadger_context
      Honeybadger.context({
        user_id: current_user&.id,
        user_username: current_user&.username
      })
    end

    rescue_from Pundit::NotAuthorizedError do |e|
      flash[:error] = "you don't seem to be authorized to do that?"
      redirect_to backend_root_path
    end

    rescue_from ActiveRecord::RecordNotFound do |e|
      flash[:error] = "sorry, couldn't find that object... (404)"
      redirect_to backend_root_path
    end
  end
end
