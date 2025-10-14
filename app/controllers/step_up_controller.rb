class StepUpController < ApplicationController
  def new
    @action = params[:action_type] # e.g., "remove_totp", "disable_2fa"
    @available_methods = current_identity.available_step_up_methods

    if @available_methods.empty?
      flash[:error] = "No 2FA methods available for verification"
      redirect_to security_path
    end
  end

  def verify
    action_type = params[:action_type]
    method = params[:method]&.to_sym
    code = params[:code]

    if code.blank?
      flash[:error] = "Please enter your verification code"
      redirect_to new_step_up_path(action_type: action_type, method: method)
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
    else
      false
    end

    unless verified
      flash[:error] = "Invalid verification code"
      redirect_to new_step_up_path(action_type: action_type, method: method)
      return
    end

    # Execute the verified action
    case action_type
    when "remove_totp"
      totp = current_identity.totp
      totp&.destroy

      if current_identity.two_factor_methods.empty?
        current_identity.update!(use_two_factor_authentication: false)
        current_identity.backup_codes.active.each(&:mark_discarded!)
      end

      redirect_to security_path, notice: "Two-factor authentication disabled"

    when "disable_2fa"
      current_identity.update!(use_two_factor_authentication: false)
      redirect_to security_path, notice: "2FA requirement disabled"

    else
      redirect_to security_path, alert: "Unknown action"
    end
  end
end
