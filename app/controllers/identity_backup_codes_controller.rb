class IdentityBackupCodesController < ApplicationController
  def index
    @backup_codes = current_identity.backup_codes.active.order(created_at: :desc)

    render layout: request.headers["HX-Request"] ? "htmx" : false
  end

  def create
    # Generate new backup codes in previewed state
    codes_to_save = []
    10.times do
      backup_code = SecureRandom.alphanumeric(10).upcase
      codes_to_save << backup_code
      current_identity.backup_codes.create!(code: backup_code, aasm_state: :previewed)
    end

    @backup_codes = current_identity.backup_codes.active.order(created_at: :desc)
    @newly_generated_codes = codes_to_save

    if request.headers["HX-Request"]
      render :index, layout: "htmx"
    else
      render :index, notice: "New backup codes generated. Save them now - you won't see them again!"
    end
  end

  def confirm
    current_identity.backup_codes.active.each(&:mark_discarded!)
    current_identity.backup_codes.previewed.each(&:mark_active!)

    @backup_codes = current_identity.backup_codes.active.order(created_at: :desc)

    if request.headers["HX-Request"]
      render :index, layout: "htmx"
    else
      redirect_to identity_backup_codes_path, notice: "Backup codes updated successfully"
    end
  end
end
