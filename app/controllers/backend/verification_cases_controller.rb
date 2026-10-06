module Backend
  class VerificationCasesController < ApplicationController
    before_action :set_case, except: [ :index, :create, :qa ]

    def index
      authorize VerificationCase
      add_breadcrumb "CASES"

      set_keyboard_shortcut(:back, backend_root_path)

      @open_cases = VerificationCase.open_cases
        .includes(:identity, :opened_by)
        .order(created_at: :asc)
        .page(params[:page]).per(20)
      @decided_cases = VerificationCase.closed_cases
        .includes(:identity, :verification)
        .order(updated_at: :desc)
        .page(params[:decided_page]).per(10)
      @qa_waiting = Verification::ManualVerificationCall.qa_candidates.where.not(reviewer_id: current_user.id).count
    end

    # qa queue: every nth decision, waiting for a second reviewer who
    # isn't the one that made it. stats cover the last 30 days.
    def qa
      authorize VerificationCase
      add_breadcrumb "CASES", backend_verification_cases_path
      add_breadcrumb "QA"

      set_keyboard_shortcut(:back, backend_verification_cases_path)

      @queue = Verification::ManualVerificationCall.qa_candidates
        .where.not(reviewer_id: current_user.id)
        .joins(:verification_case)
        .includes(:identity, :reviewer, :verification_case)
        .page(params[:page]).per(20)

      recent = Verification::ManualVerificationCall.decided.where("COALESCE(approved_at, rejected_at, verifications.created_at) >= ?", 30.days.ago)
      sampled = recent.qa_sampled
      @stats = {
        decided: recent.count,
        sampled: sampled.count,
        agree: sampled.where(sample_verdict: "agree").count,
        disagree: sampled.where(sample_verdict: "disagree").count
      }
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

    # the call itself is not recorded; the reviewer uploads one screenshot
    # showing the user and their document as the durable evidence
    def hold_call
      authorize @case

      if params[:screenshot].blank?
        flash[:error] = "a call screenshot is required to mark the call held"
        redirect_to backend_verification_case_path(@case) and return
      end

      screenshot = nil
      @case.with_lock do
        screenshot = @case.documents.create!(document_kind: "call_screenshot", source: "staff_upload", file: params[:screenshot])
        @case.hold_call!
      end
      @case.log_event!(:call_held, actor: current_user, request: request,
        data: { screenshot_document_id: screenshot.id })

      flash[:success] = "Call marked as held — record the decision below"
      redirect_to backend_verification_case_path(@case)
    end

    # reviewer sends the user back behind the booking gate to redo their
    # documents. evidence already submitted is kept; a fresh link goes out
    # with the reviewer's message.
    def request_redo
      authorize @case

      message = params[:message].to_s.strip
      if message.blank?
        flash[:error] = "Tell the user what to redo"
        redirect_to backend_verification_case_path(@case) and return
      end

      previous_inquiry_id = @case.persona_inquiry_id
      token = nil
      @case.with_lock do
        @case.request_redo!
        token = @case.rotate_access_link!
      end
      VerificationCaseMailer.redo_requested(@case, token, message).deliver_later
      @case.log_event!(:redo_requested, actor: current_user, request: request,
        data: { message: message, previous_inquiry_id: previous_inquiry_id }.compact)

      flash[:success] = "Redo requested — fresh link sent to #{@case.identity.primary_email}"
      redirect_to backend_verification_case_path(@case)
    end

    # close the case without a decision. drops the flag and kills the link
    # so the user can't get back in; a new case can be opened later.
    def withdraw
      authorize @case

      @case.with_lock { @case.withdraw! }
      @case.log_event!(:case_withdrawn, actor: current_user, request: request,
        data: { reason: params[:reason].to_s.strip.presence }.compact)

      flash[:success] = "Case withdrawn"
      redirect_to backend_verification_case_path(@case)
    end

    # second reviewer records whether they agree with a decision. the
    # model refuses self-review; a disagreement also lands as a comment so
    # the discussion happens where reviewers already look.
    def sample
      authorize @case

      verification = @case.verification
      unless @case.decided? && verification.present?
        flash[:warning] = "Only decided cases can be sampled"
        redirect_to backend_verification_case_path(@case) and return
      end
      if verification.sampled?
        flash[:warning] = "This decision has already been sampled"
        redirect_to backend_verification_case_path(@case) and return
      end

      verdict = params[:verdict].to_s
      notes = params[:notes].to_s.strip
      @case.with_lock do
        verification.record_sample!(reviewer: current_user, verdict: verdict, notes: notes)
        if verdict == "disagree"
          @case.comments.create!(author: current_user, body: "qa sample: disagree — #{notes}")
        end
      end
      @case.log_event!(:qa_sampled, actor: current_user, request: request,
        data: { verdict: verdict, verification_id: verification.id })

      flash[:success] = "QA sample recorded (#{verdict})"
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

      @case.with_lock do
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

      if decision == "approve"
        VerificationMailer.approved(verification).deliver_later
      else
        # no reason in the email — the rejection reason + details are internal
        VerificationCaseMailer.denied(@case).deliver_later
      end

      flash[:success] = "Case #{decision == 'approve' ? 'approved' : 'denied'}"
      redirect_to backend_verification_case_path(@case)
    end

    # every state change above runs under @case.with_lock, which re-reads the
    # row before aasm checks the transition, so two reviewers racing on the
    # same button get one success and one of these
    rescue_from AASM::InvalidTransition do
      flash[:warning] = "That action isn't valid for this case's current state (#{@case&.status})"
      redirect_to @case ? backend_verification_case_path(@case) : backend_verification_cases_path
    end

    rescue_from ActiveRecord::RecordInvalid do |exception|
      flash[:error] = "Could not save: #{exception.record.errors.full_messages.to_sentence}"
      redirect_to backend_verification_case_path(@case)
    end

    rescue_from Verification::ManualVerificationCall::AlreadySampled do
      flash[:warning] = "This decision has already been sampled"
      redirect_to backend_verification_case_path(@case)
    end

    private

    def set_case
      @case = VerificationCase
        .includes(:identity, :opened_by, :verification, documents: { file_attachment: :blob })
        .find_by_public_id!(params[:id])
    end

    def deliver_link!
      token = @case.rotate_access_link!
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
        checklist: checklist
      )
    end
  end
end
