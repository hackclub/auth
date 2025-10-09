class IdentityBackupCodesController < ApplicationController
  def index
    @backup_codes = current_identity.backup_codes.active.order(created_at: :desc)
    
    render layout: request.headers["HX-Request"] ? "htmx" : false
  end

  def create
    # Regenerate backup codes
    current_identity.backup_codes.active.each(&:mark_discarded!)
    
    codes_to_save = []
    10.times do
      backup_code = SecureRandom.alphanumeric(10).upcase
      codes_to_save << backup_code
      current_identity.backup_codes.create!(code: backup_code, aasm_state: :previewed)
    end
    current_identity.backup_codes.previewed.each(&:mark_active!)
    
    @backup_codes = current_identity.backup_codes.active.order(created_at: :desc)
    @newly_generated_codes = codes_to_save
    
    if request.headers["HX-Request"]
      render :index, layout: "htmx"
    else
      render :index, notice: "New backup codes generated. Save them now - you won't see them again!"
    end
  end
end
