class PasskeyLoginsController < ApplicationController
  include WebauthnAuthenticatable
  include SafeUrlValidation
  include AhoyAnalytics

  skip_before_action :authenticate_identity!
  before_action :ensure_no_user!

  PASSKEY_LOGIN_SESSION_KEY = :passkey_login_challenge

  def options
    options = WebAuthn::Credential.options_for_get(
      allow: [],
      user_verification: "required"
    )

    session[PASSKEY_LOGIN_SESSION_KEY] = options.challenge
    render json: options
  end

  def verify
    credential_data = JSON.parse(params[:credential_data])

    credential = find_and_verify_discoverable_webauthn_credential(
      credential_data,
      session_key: PASSKEY_LOGIN_SESSION_KEY
    )

    unless credential
      flash[:error] = "Passkey not found. Try using your email instead."
      redirect_to login_path(return_to: params[:return_to])
      return
    end

    identity = credential.identity

    attempt = LoginAttempt.create!(
      identity: identity,
      authentication_factors: { webauthn: true },
      provenance: "login",
      next_action: "home",
      return_to: url_from(params[:return_to])
    )

    attempt.mark_complete! if attempt.may_mark_complete?

    unless attempt.complete?
      flash[:error] = "Unable to complete authentication"
      redirect_to login_path(return_to: params[:return_to])
      return
    end

    ident_session = sign_in(identity: identity)
    attempt.update!(session: ident_session)

    track_event(
      "login.completed",
      has_mfa: identity.use_two_factor_authentication?,
      next_action: attempt.next_action,
      scenario: nil
    )

    flash[:success] = "Logged in!"
    redirect_to url_from(params[:return_to]) || root_path
  rescue WebauthnCredentialCompromisedError
    flash[:error] = "Security issue detected with your passkey. It has been disabled for your protection. Please use another login method or register a new passkey."
    redirect_to login_path(return_to: params[:return_to])
  rescue WebAuthn::Error
    flash[:error] = "Passkey verification failed. Please try again or use your email."
    redirect_to login_path(return_to: params[:return_to])
  rescue JSON::ParserError
    flash[:error] = "Something went wrong. Please try again."
    redirect_to login_path(return_to: params[:return_to])
  end
end
