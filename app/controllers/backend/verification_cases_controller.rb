module Backend
  class VerificationCasesController < ApplicationController
    before_action :set_case, except: [ :index, :create ]

    def index
      authorize VerificationCase
      add_breadcrumb "CASES"

      set_keyboard_shortcut(:back, backend_root_path)

      @open_cases = VerificationCase.open_cases
        .includes(:identity, :opened_by)
        .order(created_at: :asc)
        .page(params[:page]).per(20)
      @decided_cases = VerificationCase.where(status: %w[approved denied])
        .includes(:identity, :verification)
        .order(updated_at: :desc)
        .page(params[:decided_page]).per(10)
    end

    def show
      authorize @case
      add_breadcrumb "CASES", backend_verification_cases_path
      add_breadcrumb @case.public_id

      set_keyboard_shortcut(:back, backend_verification_cases_path)

      @events = @case.events.recent_first.includes(:actor)
      @documents = @case.documents
      @comments = @case.comments.chronological.includes(author: :identity)
    end

    # staff entry point: user emailed identity@, staff opens a case.
    # enables the flipper flag + sends the single-use link.
    def create
      authorize VerificationCase

      identity = Identity.find_by_public_id!(params[:identity_id])

      if identity.verification_cases.open_cases.exists?
        flash[:warning] = "This identity already has an open case"
        redirect_to backend_identity_path(identity) and return
      end

      @case = VerificationCase.create!(
        identity: identity,
        opened_by: current_user,
        skip_persona: params[:skip_persona] == "1"
      )
      @case.enable_flag!
      deliver_link!

      @case.log_event!(:case_opened, actor: current_user, request: request,
        data: { skip_persona: @case.skip_persona? })

      flash[:success] = "Case opened and link sent to #{identity.primary_email}"
      redirect_to backend_verification_case_path(@case)
    end

    def resend_link
      authorize @case

      deliver_link!
      @case.log_event!(:link_resent, actor: current_user, request: request)

      flash[:success] = "Fresh link sent to #{@case.identity.primary_email}"
      redirect_to backend_verification_case_path(@case)
    end

    def hold_call
      authorize @case

      @case.hold_call!
      @case.log_event!(:call_held, actor: current_user, request: request)

      flash[:success] = "Call marked as held — record the decision below"
      redirect_to backend_verification_case_path(@case)
    end

    def comment
      authorize @case

      @case.comments.create!(author: current_user, body: params[:body])

      redirect_to backend_verification_case_path(@case)
    end

    def decide
      authorize @case

      decision = params[:decision]
      unless %w[approve deny].include?(decision)
        flash[:error] = "Decision must be approve or deny"
        redirect_to backend_verification_case_path(@case) and return
      end

      verification = build_verification

      ActiveRecord::Base.transaction do
        verification.save!
        @case.update!(verification: verification)

        if decision == "approve"
          verification.approve!
          @case.approve!
        else
          verification.mark_as_rejected!(params[:rejection_reason], params[:rejection_reason_details])
          @case.deny!
        end
      end

      @case.log_event!(:"decision_#{decision}", actor: current_user, request: request,
        data: { verification_id: verification.id, checklist: verification.checklist })
      verification.create_activity(key: "verification.#{decision == 'approve' ? 'approve' : 'reject'}",
        owner: current_user, recipient: @case.identity)

      VerificationMailer.approved(verification).deliver_later if decision == "approve"

      flash[:success] = "Case #{decision == 'approve' ? 'approved' : 'denied'}"
      redirect_to backend_verification_case_path(@case)
    end

    rescue_from AASM::InvalidTransition do
      flash[:warning] = "That action isn't valid for this case's current state (#{@case&.status})"
      redirect_to @case ? backend_verification_case_path(@case) : backend_verification_cases_path
    end

    rescue_from ActiveRecord::RecordInvalid do |exception|
      flash[:error] = "Could not save: #{exception.record.errors.full_messages.to_sentence}"
      redirect_to backend_verification_case_path(@case)
    end

    private

    def set_case
      @case = VerificationCase
        .includes(:identity, :opened_by, :verification, documents: { file_attachment: :blob })
        .find_by_public_id!(params[:id])
    end

    def deliver_link!
      token = @case.generate_access_token!
      @case.send_link!
      VerificationCaseMailer.invitation(@case, token).deliver_later
    end

    def build_verification
      checklist = {}
      Verification::ManualVerificationCall::CHECKLIST_ITEMS.each_key do |item|
        checklist[item] = params.dig(:checklist, item) == "yes" if params.dig(:checklist, item).present?
      end
      # no selfie on this case (persona-less direct upload) — nothing to
      # compare the document against, so the item is recorded as n/a
      checklist["doc_matches_selfie"] = nil unless @case.selfie_available?
      checklist["confidence"] = params[:confidence]
      checklist["notes"] = params[:notes].presence

      Verification::ManualVerificationCall.new(
        identity: @case.identity,
        reviewer: current_user,
        checklist: checklist,
        expires_at: @case.alternative? ? VerificationCase::ALTERNATIVE_DOCS_EXPIRY.from_now : nil
      )
    end
  end
end
