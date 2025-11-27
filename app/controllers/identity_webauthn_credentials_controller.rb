class IdentityWebauthnCredentialsController < ApplicationController
  def index
    @webauthn_credentials = current_identity.webauthn_credentials.order(created_at: :desc)
    render layout: request.headers["HX-Request"] ? "htmx" : false
  end

  def new
    render layout: request.headers["HX-Request"] ? "htmx" : false
  end

  def options
    challenge = WebAuthn::Credential.options_for_create(
      user: {
        id: current_identity.webauthn_user_id,
        name: current_identity.primary_email,
        display_name: "#{current_identity.first_name} #{current_identity.last_name}"
      },
      exclude: current_identity.webauthn_credentials.raw_credential_ids,
      authenticator_selection: {
        user_verification: "preferred",
        resident_key: "preferred"
      }
    )

    # store the challenge in the session to verify it later!
    session[:webauthn_registration_challenge] = challenge.challenge

    render json: challenge
  end

  def create
    begin
      credential_data = JSON.parse(params[:credential_data])
      nickname = params[:nickname]

      webauthn_credential = WebAuthn::Credential.from_create(credential_data)

      webauthn_credential.verify(session[:webauthn_registration_challenge])

      credential = current_identity.webauthn_credentials.create!(
        webauthn_id: webauthn_credential.id,
        webauthn_public_key: webauthn_credential.public_key,
        nickname: nickname.presence,
        sign_count: webauthn_credential.sign_count
      )

      session.delete(:webauthn_registration_challenge)

      flash[:success] = t(".successfully_added")
      redirect_to security_path
    rescue WebAuthn::Error => e
      Rails.logger.error "WebAuthn registration error: #{e.message}"
      flash[:error] = "Passkey registration failed. Please try again."
      render :new, status: :unprocessable_entity
    rescue => e
      Rails.logger.error "Unexpected WebAuthn registration error: #{e.message}"
      flash[:error] = "An unexpected error occurred. Please try again."
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    credential = current_identity.webauthn_credentials.find(params[:id])
    credential.destroy

    flash[:success] = t(".successfully_removed")
    redirect_to security_path
  end
end
