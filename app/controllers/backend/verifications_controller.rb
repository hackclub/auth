module Backend
  class VerificationsController < ApplicationController
    before_action :set_verification, only: [ :show, :approve, :reject, :ignore ]

    hint :list_navigation, on: [ :index, :pending ]
    hint :pagination, on: [ :index, :pending ]
    hint :back_navigation, on: [ :index, :pending ]
    hint :verification_review, on: :show

    def index
      authorize Verification

      set_keyboard_shortcut(:back, backend_root_path)

      @recent_verifications = Verification.includes(:identity, :identity_document)
        .where.not(status: "pending")
        .order(updated_at: :desc)
        .page(params[:page])
        .per(20)
    end

    def pending
      authorize Verification

      set_keyboard_shortcut(:back, backend_root_path)

      @pending_verifications = Verification.includes(:identity, :identity_document, identity_document: { files_attachments: :blob })
        .where(status: "pending")
        .order(created_at: :asc)
        .page(params[:page])
        .per(20)
      @average_hangtime = @pending_verifications.average("EXTRACT(EPOCH FROM (NOW() - COALESCE(verifications.pending_at, verifications.created_at)))").to_i if @pending_verifications.any?
    end

    def show
      authorize @verification

      set_keyboard_shortcut(:back, pending_backend_verifications_path)
      if @verification.pending?
        set_keyboard_shortcut(:approve_ysws, approve_backend_verification_path(@verification))
        set_keyboard_shortcut(:approve_not_ysws, approve_backend_verification_path(@verification))
        set_keyboard_shortcut(:focus_reject, true)
      end

      # Fetch verification activities
      verification_activities = @verification.activities.includes(:owner)

      # Fetch break glass activities efficiently with a single query
      break_glass_activities = []
      unless @verification.is_a?(Verification::VouchVerification)
        @relevant_object = @verification.identity_document || @verification.aadhaar_record
        break_glass_record_ids = @relevant_object&.break_glass_records&.pluck(:id) || []
        break_glass_activities = PublicActivity::Activity
          .where(trackable_type: "BreakGlassRecord", trackable_id: break_glass_record_ids)
          .includes(:trackable, :owner)
      end
      @activities = (verification_activities + break_glass_activities).sort_by(&:created_at).reverse
    end

    def approve
      authorize @verification, :approve?

      @verification.approve!

      # Set YSWS eligibility if provided
      if params[:ysws_eligible].present?
        ysws_eligible = params[:ysws_eligible] == "true"
        @verification.identity.update!(ysws_eligible: ysws_eligible)

        # Send appropriate mailer based on YSWS eligibility and adult program status
        if ysws_eligible || @verification.identity.came_in_through_adult_program
          VerificationMailer.approved(@verification).deliver_now
        else
          IdentityMailer.approved_but_ysws_ineligible(@verification.identity).deliver_now
          Slack::NotifyGuardiansJob.perform_later(@verification.identity)
        end

        eligibility_text = ysws_eligible ? "YSWS eligible" : "YSWS ineligible"
        flash[:success] = "Document approved and marked as #{eligibility_text}!"
      else
        VerificationMailer.approved(@verification).deliver_now
        flash[:success] = "Document approved successfully!"
      end

      @verification.create_activity(key: "verification.approve", owner: current_user, recipient: @verification.identity, parameters: { ysws_eligible: ysws_eligible })

      redirect_to pending_backend_verifications_path
    end

    def reject
      authorize @verification, :reject?

      reason = params[:rejection_reason]
      details = params[:rejection_reason_details]
      internal_comment = params[:internal_rejection_comment]

      if reason.blank?
        flash[:error] = "Rejection reason is required"
        redirect_to backend_verification_path(@verification)
        return
      end

      @verification.mark_as_rejected!(reason, details)
      @verification.internal_rejection_comment = internal_comment if internal_comment.present?
      @verification.save!

      @verification.create_activity(key: "verification.reject", owner: current_user, recipient: @verification.identity, parameters: { reason: reason, details: details, internal_comment: internal_comment })

      flash[:success] = "Document rejected with feedback"
      redirect_to pending_backend_verifications_path
    end

    def ignore
      authorize @verification, :ignore?

      if params[:reason].blank?
        flash[:alert] = "Reason is required to ignore verification"
        redirect_to backend_verification_path(@verification) and return
      end

      @verification.update!(
        ignored_at: Time.current,
        ignored_reason: params[:reason],
      )

      @verification.create_activity(
        :ignored,
        owner: current_user,
        parameters: { reason: params[:reason] },
      )

      flash[:notice] = "Verification ignored successfully"
      redirect_to backend_identity_path(@verification.identity)
    end

    rescue_from AASM::InvalidTransition, with: :oops

    private

    def set_verification
      @verification = Verification.includes(:identity, identity_document: :break_glass_records).find_by_public_id!(params[:id])
    end

    def oops
      flash[:warning] = "This verification has already been processed?"
      redirect_to pending_backend_verifications_path
    end
  end
end
