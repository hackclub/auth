# frozen_string_literal: true

module Backend
  class DeletionsController < ApplicationController
    def index
      authorize Deletion
      add_breadcrumb "DELETIONS"

      set_keyboard_shortcut(:back, backend_root_path)

      @deletions = Deletion.order(created_at: :desc)
    end

    def show
      @deletion = Deletion.find(params[:id])
      authorize @deletion
      add_breadcrumb "DELETIONS", backend_deletions_path
      add_breadcrumb "##{@deletion.id}"
    end

    def new
      authorize Deletion, :create?
      add_breadcrumb "DELETIONS", backend_deletions_path
      add_breadcrumb "execute"
    end

    def confirm
      authorize Deletion, :create?
      add_breadcrumb "DELETIONS", backend_deletions_path
      add_breadcrumb "confirm"

      identifier = params[:identifier].to_s.strip
      privacy_ref = params[:privacy_request_reference].to_s.strip

      if identifier.blank?
        return redirect_to new_backend_deletion_path, alert: "Identity identifier is required."
      end

      @identity = resolve_identity(identifier)
      unless @identity
        return redirect_to new_backend_deletion_path, alert: "Identity not found for: #{identifier}"
      end

      @privacy_request_reference = privacy_ref
      @identifier = identifier
    end

    def create
      authorize Deletion, :create?

      identifier = params[:identifier].to_s.strip
      privacy_ref = params[:privacy_request_reference].to_s.strip

      if identifier.blank?
        return redirect_to new_backend_deletion_path, alert: "Identity identifier is required."
      end

      if privacy_ref.blank?
        return redirect_to new_backend_deletion_path, alert: "Privacy request reference is required."
      end

      identity = resolve_identity(identifier)
      unless identity
        return redirect_to new_backend_deletion_path, alert: "Identity not found for: #{identifier}"
      end

      log_lines = []
      logger = ->(msg) { log_lines << msg }
      original_email = identity.primary_email

      DeletionService.execute_deletion(identity, privacy_request_reference: privacy_ref, logger: logger)

      deletion = Deletion.find_by(email_hash: Deletion.hash_email(original_email))
      flash[:deletion_log] = log_lines
      redirect_to backend_deletion_path(deletion), notice: "Deletion executed for #{identity.public_id}."
    rescue DeletionService::Error => e
      redirect_to new_backend_deletion_path, alert: e.message
    end

    private

    def resolve_identity(identifier)
      scope = Identity.with_deleted
      if identifier.match?(/\A\d+\z/)
        scope.find_by(id: identifier)
      elsif identifier.start_with?("ident!")
        scope.find_by_public_id(identifier)
      else
        scope.find_by(primary_email: identifier.downcase)
      end
    end
  end
end
