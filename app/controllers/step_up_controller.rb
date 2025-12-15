class StepUpController < ApplicationController
  helper_method :step_up_cancel_path

  def new
    @action = params[:action_type] # e.g., "remove_totp", "disable_2fa", "oidc_reauth", "email_change"
    @return_to = params[:return_to]
    @available_methods = current_identity.available_step_up_methods
    @available_methods << :email unless @action == "email_change" # Email fallback not available for email change (already verifying old email)
    @code_sent = params[:code_sent].present?
  end

  def send_email_code
    if params[:action_type] == "email_change"
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

    if action_type == "email_change" && method == :email
      flash[:error] = "Email verification is not available for this action"
      redirect_to new_step_up_path(action_type: action_type, return_to: params[:return_to])
      return
    end

    # Verify based on the method they chose
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

    # Mark step-up as completed on the identity session
    current_session.update!(last_step_up_at: Time.current)

    # Execute the verified action
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
      # OIDC re-authentication completed, redirect back to OAuth flow
      safe_path = safe_internal_redirect(params[:return_to])
      redirect_to safe_path || root_path

    when "email_change"
      # Email change step-up completed, redirect to the email change form
      safe_path = safe_internal_redirect(params[:return_to])
      redirect_to safe_path || new_email_change_path

    else
      redirect_to security_path, alert: "Unknown action"
    end
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

  # Prevent open redirect attacks - only allow internal paths
  def safe_internal_redirect(return_to)
    return nil if return_to.blank?

    uri = URI.parse(return_to) rescue nil
    return nil unless uri

    # Reject if it has a scheme or host (absolute URL or protocol-relative like //evil.com)
    return nil if uri.scheme || uri.host

    # Must be a path starting with /
    return nil unless uri.path&.start_with?("/")

    # Return just the path + query string
    [ uri.path, uri.query ].compact.join("?")
  end
end
