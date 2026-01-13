class StepUpController < ApplicationController
  include WebauthnAuthenticatable

  helper_method :step_up_cancel_path

  WEBAUTHN_SESSION_KEY = :step_up_webauthn_challenge
  ACTIONS_WITHOUT_EMAIL_FALLBACK = %w[email_change disable_2fa remove_passkey].freeze

  def new
    @action = params[:action_type] # e.g., "remove_totp", "disable_2fa", "oidc_reauth", "email_change"
    @return_to = params[:return_to]
    @available_methods = current_identity.available_step_up_methods
    @available_methods << :email unless @action.in?(ACTIONS_WITHOUT_EMAIL_FALLBACK)
    @code_sent = params[:code_sent].present?
  end

  def webauthn_options
    options = generate_webauthn_authentication_options(
      current_identity,
      session_key: WEBAUTHN_SESSION_KEY,
      user_verification: "required"
    )
    render json: options
  end

  def verify_webauthn
    credential_data = JSON.parse(params[:credential_data])

    credential = verify_webauthn_credential(
      current_identity,
      credential_data: credential_data,
      session_key: WEBAUTHN_SESSION_KEY
    )

    unless credential
      flash[:error] = "Passkey not found"
      redirect_to new_step_up_path(action_type: params[:action_type], return_to: params[:return_to])
      return
    end

    complete_step_up(params[:action_type], params[:return_to])
  rescue WebauthnCredentialCompromisedError => e
    Rails.logger.warn "Step-up blocked: compromised credential detected for identity #{current_identity.id}"
    flash[:error] = "Security issue detected with your passkey. It has been disabled for your protection. Please use another verification method or register a new passkey."
    redirect_to new_step_up_path(action_type: params[:action_type], return_to: params[:return_to])
  rescue WebAuthn::Error => e
    Rails.logger.error "Step-up WebAuthn error: verification failed"
    flash[:error] = "Passkey verification failed. Please try again."
    redirect_to new_step_up_path(action_type: params[:action_type], method: :webauthn, return_to: params[:return_to])
  rescue => e
    Rails.logger.error "Unexpected step-up WebAuthn error: #{e.class.name}"
    flash[:error] = "An unexpected error occurred. Please try again."
    redirect_to new_step_up_path(action_type: params[:action_type], return_to: params[:return_to])
  end

  def send_email_code
    if params[:action_type].in?(ACTIONS_WITHOUT_EMAIL_FALLBACK)
      flash[:error] = "Email verification is not available for this action"
      redirect_to new_step_up_path(action_type: params[:action_type], return_to: params[:return_to])
      return
    end

    send_step_up_email_code
    flash[:notice] = "A verification code has been sent to your email"
    redirect_to new_step_up_path(
      action_type: params[:action_type],
      method: :email,
      return_to: params[:return_to],
      code_sent: true
    )
  end

  def verify
    action_type = params[:action_type]
    method = params[:method]&.to_sym
    code = params[:code]

    if code.blank?
      flash[:error] = "Please enter your verification code"
      redirect_to new_step_up_path(action_type: action_type, method: method, return_to: params[:return_to], code_sent: method == :email)
      return
    end

    if action_type.in?(ACTIONS_WITHOUT_EMAIL_FALLBACK) && method == :email
      flash[:error] = "Email verification is not available for this action"
      redirect_to new_step_up_path(action_type: action_type, return_to: params[:return_to])
      return
    end

    verified = case method
    when :totp
      totp = current_identity.totp
      totp&.verify(code, drift_behind: 1, drift_ahead: 1)

    when :backup_code
      backup = current_identity.backup_codes.active.find { |bc| bc.authenticate_code(code) }
      if backup
        backup.mark_used!
        true
      else
        false
      end

    when :email
      login_code = current_identity.v2_login_codes.active.find_by(code: code.delete("-").strip)
      if login_code
        login_code.update!(used_at: Time.current)
        true
      else
        false
      end
    else
      false
    end

    unless verified
      flash[:error] = "Invalid verification code"
      redirect_to new_step_up_path(action_type: action_type, method: method, return_to: params[:return_to], code_sent: method == :email)
      return
    end

    complete_step_up(action_type, params[:return_to])
  end

  def resend_email
    if params[:action_type] == "email_change"
      flash[:error] = "Email verification is not available for this action"
      redirect_to new_step_up_path(action_type: params[:action_type], return_to: params[:return_to])
      return
    end

    send_step_up_email_code
    flash[:notice] = "A new code has been sent to your email"
    redirect_to new_step_up_path(
      action_type: params[:action_type],
      method: :email,
      return_to: params[:return_to],
      code_sent: true
    )
  end

  private

  def complete_step_up(action_type, return_to)
    current_session.record_step_up!(action: action_type)

    case action_type
    when "remove_totp"
      totp = current_identity.totp
      totp&.destroy
      TwoFactorMailer.authentication_method_disabled(current_identity).deliver_later

      if current_identity.two_factor_methods.empty?
        current_identity.update!(use_two_factor_authentication: false)
        current_identity.backup_codes.active.each(&:mark_discarded!)
      end

      consume_step_up!
      redirect_to security_path, notice: "Two-factor authentication disabled"

    when "disable_2fa"
      current_identity.update!(use_two_factor_authentication: false)
      TwoFactorMailer.required_authentication_disabled(current_identity).deliver_later
      consume_step_up!
      redirect_to security_path, notice: "2FA requirement disabled"

    when "oidc_reauth"
      safe_path = safe_internal_redirect(return_to)
      redirect_to safe_path || root_path

    when "email_change"
      safe_path = safe_internal_redirect(return_to)
      redirect_to safe_path || new_email_change_path

    when "remove_passkey"
      credential_id = session.delete(:pending_destroy_credential_id)
      if credential_id
        redirect_to identity_webauthn_credential_path(credential_id), method: :delete
      else
        redirect_to security_path
      end

    else
      redirect_to security_path, alert: "Unknown action"
    end
  end

  def send_step_up_email_code
    login_code = current_identity.v2_login_codes.create!
    IdentityMailer.v2_login_code(login_code).deliver_later
  end

  def step_up_cancel_path(action_type)
    case action_type
    when "email_change"
      edit_identity_path
    else
      security_path
    end
  end

  def safe_internal_redirect(return_to)
    return nil if return_to.blank?

    uri = URI.parse(return_to) rescue nil
    return nil unless uri

    return nil if uri.scheme || uri.host
    return nil unless uri.path&.start_with?("/")

    [ uri.path, uri.query ].compact.join("?")
  end
end
