class IdentityTotpsController < ApplicationController
  def index
    @totp = current_identity.totp

    render layout: request.headers["HX-Request"] ? "htmx" : false
  end

  def new
    @totp = current_identity.totps.build

    if @totp.save
      render :show, layout: request.headers["HX-Request"] ? "htmx" : false
    else
      render :index, layout: request.headers["HX-Request"] ? "htmx" : false, status: :unprocessable_entity
    end
  end

  def verify
    @totp = current_identity.totps.find(params[:id])
    code = params[:code]

    if @totp.verify(code, drift_behind: 1, drift_ahead: 1)
      @totp.mark_verified!

      # Generate backup codes if this is their first 2FA method
      codes_generated = []
      if current_identity.backup_codes.active.empty?
        codes_generated = generate_backup_codes_for_identity(current_identity)
      end

      if codes_generated.any?
        @newly_generated_codes = codes_generated
        render :backup_codes, layout: request.headers["HX-Request"] ? "htmx" : false
      elsif request.headers["HX-Request"]
        response.headers["HX-Redirect"] = security_path
        head :ok
      else
        redirect_to security_path, notice: "TOTP setup complete! Enable 2FA enforcement to require it on login."
      end
    else
      flash.now[:error] = "Invalid code, please try again."
      status = request.headers["HX-Request"] ? :ok : :unprocessable_entity
      render :show, layout: request.headers["HX-Request"] ? "htmx" : false, status: status
    end
  rescue ActiveRecord::RecordNotFound
    if request.headers["HX-Request"]
      response.headers["HX-Redirect"] = security_path
      head :ok
    else
      redirect_to security_path, alert: "TOTP not found"
    end
  end

  def destroy
    redirect_to new_step_up_path(action_type: "remove_totp")
  end

  private

  def generate_backup_codes_for_identity(identity)
    codes_generated = []
    10.times do
      backup_code = SecureRandom.alphanumeric(10).upcase
      codes_generated << backup_code
      identity.backup_codes.create!(code: backup_code, aasm_state: :previewed)
    end
    identity.backup_codes.previewed.each(&:mark_active!)
    codes_generated
  end
end
