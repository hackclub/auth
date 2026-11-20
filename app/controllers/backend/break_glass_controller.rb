# frozen_string_literal: true

class Backend::BreakGlassController < Backend::ApplicationController
  def create
    @break_glassable = find_break_glassable

    authorize BreakGlassRecord

    break_glass_record = BreakGlassRecord.new(
      backend_user: current_user,
      break_glassable: @break_glassable,
      reason: params[:reason],
      accessed_at: Time.current,
    )

    # the case audit event is written in the same transaction as the record,
    # so a failed save (blank reason) or a create! error leaves no trace of
    # access that never happened. the event trail is append-only.
    saved = BreakGlassRecord.transaction do
      break_glass_record.save.tap { |ok| log_case_event!(break_glass_record) if ok }
    end

    if saved
      redirect_back(fallback_location: backend_root_path, notice: "Access granted. #{document_type.capitalize} is now visible.")
    else
      redirect_back(fallback_location: backend_root_path, alert: "Failed to grant access: #{break_glass_record.errors.full_messages.join(", ")}")
    end
  end

  private

  # it'd be neat if this was polymorphic
  def find_break_glassable
    case params[:break_glassable_type]
    when "Identity::Document"
      Identity::Document.find(params[:break_glassable_id])
    when "Identity::AadhaarRecord"
      Identity::AadhaarRecord.find(params[:break_glassable_id])
    when "Identity::PersonaRecord"
      Identity::PersonaRecord.find(params[:break_glassable_id])
    when "Identity"
      Identity.find_by_public_id!(params[:break_glassable_id])
    when "VerificationCase::Document"
      VerificationCase::Document.find(params[:break_glassable_id])
    else
      raise ArgumentError, "Invalid break_glassable_type: #{params[:break_glassable_type]}"
    end
  end

  # case documents carry their own audit trail on the case, alongside the
  # BreakGlassRecord. reason comes from the saved record, not raw params.
  def log_case_event!(record)
    doc = record.break_glassable
    return unless doc.is_a?(VerificationCase::Document)

    doc.verification_case.log_event!(:document_break_glass, actor: current_user,
      data: { document_id: doc.id, reason: record.reason }, request: request)
  end

  # TODO: these should be model methods! @break_glassable.try(:thing_name) || "item"
  def document_type
    case @break_glassable.class.name
    when "Identity::Document"
      "document"
    when "Identity::AadhaarRecord"
      "aadhaar record"
    when "Identity::PersonaRecord"
      "persona record"
    when "Identity"
      "identity"
    when "VerificationCase::Document"
      "case document"
    else
      "item"
    end
  end
end
