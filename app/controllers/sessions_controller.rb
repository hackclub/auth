class SessionsController < ApplicationController
  skip_before_action :authenticate_identity!, only: [ :new, :create, :check_your_email, :verify, :confirm ]

  def new
  end

  def create
    params[:email]&.downcase!
    @identity = Identity.find_by(primary_email: params[:email])

    if @identity
      return_url = params[:return_url] || session[:oauth_return_to]

      @login_code = Identity::LoginCode.generate(@identity, return_url: return_url)

      if Rails.env.production?
        IdentityMailer.login_code(@login_code).deliver_later
      else
        IdentityMailer.login_code(@login_code).deliver_now
      end

      redirect_to check_your_email_sessions_path, notice: "Login code sent to #{@identity.primary_email}"
    else
      flash[:info] = "we don't seem to have that email on file – let's get you on board!"
      session[:stashed_data] ||= {}
      session[:stashed_data]["prefill"] ||= {}
      session[:stashed_data]["prefill"]["email"] = params[:email]
      redirect_to basic_info_onboarding_path
    end
  end

  def check_your_email
  end

  def verify
    token = params[:token]

    unless token
      redirect_to check_your_email_sessions_path, alert: "No login token provided."
      return
    end

    @login_code = Identity::LoginCode.valid.find_by(token: token)

    if @login_code
    else
      redirect_to new_sessions_path, alert: "Invalid or expired login link."
    end
  end

  def confirm
    token = params[:token]

    unless token
      redirect_to new_sessions_path, alert: "No login token provided."
      return
    end

    @login_code = Identity::LoginCode.valid.find_by(token: token)

    if @login_code
      @login_code.mark_used!

      session[:identity_id] = @login_code.identity.id

      redirect_path = determine_redirect_after_login(@login_code)
      flash[:success] = "You're in!"
      redirect_to redirect_path
    else
      redirect_to new_sessions_path, alert: "Invalid or expired login link."
    end
  end

  def destroy
    session[:identity_id] = nil
    redirect_to root_path, notice: "Successfully signed out"
  end

  private

  def deliver_login_code(login_code)
    login_link = verify_sessions_url(token: login_code.token)
    Rails.logger.info "LOGIN LINK for #{login_code.identity.primary_email}:"
    Rails.logger.info login_link
    Rails.logger.info "Token: #{login_code.token}"
  end

  def determine_redirect_after_login(login_code)
    if login_code.return_url.present? && safe_return_url?(login_code.return_url)
      return login_code.return_url
    end

    identity = login_code.identity

    if identity.verification_status != "verified"
      determine_onboarding_step(identity)
    else
      session[:oauth_return_to] || root_path
    end
  end

  def safe_return_url?(url)
    return false if url.blank?

    begin
      uri = URI.parse(url)
      uri.relative? || uri.host == request.host
    rescue URI::InvalidURIError
      false
    end
  end

  def determine_onboarding_step(identity)
    identity.onboarding_redirect_path
  end
end
