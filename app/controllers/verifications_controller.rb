class VerificationsController < ApplicationController
  include Wicked::Wizard
  before_action :set_identity

  steps :document

  def new
    # Redirect to status page if they shouldn't be submitting
    status = current_identity.verification_status
    if status == "pending" || status == "verified" || status == "ineligible"
      redirect_to verification_status_path
      return
    end
    
    redirect_to verification_step_path(:document)
  end

  def status
    @identity = current_identity
    @status = @identity.verification_status
    @latest_verification = @identity.latest_verification
  end

  def show
    @identity = current_identity
    
    # Redirect to status page if they shouldn't be filling out the form
    status = @identity.verification_status
    if status == "pending" || status == "verified" || status == "ineligible"
      redirect_to verification_status_path
      return
    end
    
    case step
    when :document
      setup_document_step
    end

    render_wizard
  end

  def update
    @identity = current_identity
    
    case step
    when :document
      handle_document_submission
    end
  end

  private

  def set_identity
    @identity = current_identity
  end

  def setup_document_step
    @is_resubmission = @identity.needs_resubmission?
    @rejected_verifications = @identity.rejected_verifications_needing_resubmission if @is_resubmission
    @document = Identity::Document.new(identity: @identity)
  end

  def handle_document_submission
    @document = Identity::Document.new(document_params)
    @document.identity = @identity

    # Update Aadhaar number if provided (for India)
    if params[:aadhaar_number].present?
      @identity.aadhaar_number = params[:aadhaar_number]
      unless @identity.save
        @is_resubmission = @identity.needs_resubmission?
        @rejected_verifications = @identity.rejected_verifications_needing_resubmission if @is_resubmission
        @document.errors.add(:base, "Aadhaar number: #{@identity.errors[:aadhaar_number].join(', ')}")
        render_wizard
        return
      end
    end

    if @document.save
      # Create the verification
      verification = Verification::DocumentVerification.create!(
        identity: @identity,
        identity_document: @document,
        status: :pending
      )

      flash[:success] = "Your documents have been submitted for review! We'll email you when they're processed."
      redirect_to root_path
    else
      @is_resubmission = @identity.needs_resubmission?
      @rejected_verifications = @identity.rejected_verifications_needing_resubmission if @is_resubmission
      render_wizard
    end
  end

  def document_params
    params.require(:identity_document).permit(:document_type, files: [])
  end
end
