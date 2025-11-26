class IdentityWebauthnCredentialsController < ApplicationController
  def index
    @webauthn_credentials = current_identity.webauthn_credentials.order(created_at: :desc)
    render layout: request.headers["HX-Request"] ? "htmx" : false
  end

  def new
    render layout: request.headers["HX-Request"] ? "htmx" : false
  end

  # Generate registration options (challenge) for WebAuthn credential creation
  def options
    user_id_binary = [ current_identity.id ].pack("Q>") # 64-bit unsigned big-endian
    user_id_base64 = Base64.urlsafe_encode64(user_id_binary, padding: false)

    challenge = WebAuthn::Credential.options_for_create(
      user: {
        id: user_id_base64,
        name: current_identity.primary_email,
        display_name: "#{current_identity.first_name} #{current_identity.last_name}"
      },
      exclude: current_identity.webauthn_credentials.pluck(:external_id).map { |id| Base64.urlsafe_decode64(id) },
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
      # Parse the JSON request body manually since Rails doesn't auto-parse for non-API controllers
      # (is this wrong? probably...)
      request_body = request.body.read
      request.body.rewind
      body_params = JSON.parse(request_body)

      nickname = body_params["nickname"]
      credential_data = body_params.except("nickname")

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
      render json: { success: true, redirect_url: security_path }
    rescue WebAuthn::Error => e
      Rails.logger.error "WebAuthn registration error: #{e.message}"
      render json: { success: false, error: e.message }, status: :unprocessable_entity
    end
  end

  def destroy
    credential = current_identity.webauthn_credentials.find(params[:id])
    credential.destroy

    flash[:success] = t(".successfully_removed")
    redirect_to security_path
  end
end
