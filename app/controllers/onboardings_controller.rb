# HERE BE DRAGONS.
# this controller sucks!
# replace this with zombocom/wicked or something, this is a terrible way to do a wizard
class OnboardingsController < ApplicationController
  skip_before_action :authenticate_identity!, only: [ :show, :welcome, :signin, :basic_info, :create_basic_info ]
  before_action :ensure_correct_step, except: [ :show, :create_basic_info, :create_document, :submit_aadhaar, :address, :create_address, :signin, :continue, :submitted ]
  before_action :set_identity, except: [ :show, :welcome, :signin, :basic_info, :create_basic_info ]
  before_action :ensure_aadhaar_makes_sense, only: [ :aadhaar, :submit_aadhaar, :aadhaar_step_2 ]

  ONBOARDING_STEPS = %w[welcome basic_info document aadhaar address submitted].freeze

  def show
    redirect_to determine_current_step
  end

  def welcome
  end

  def signin
    flash[:warning] = nil
    redirect_to new_sessions_path
  end

  def basic_info
    @identity = current_identity || Identity.new
  end

  def create_basic_info
    return redirect_to_current_step if current_identity&.persisted?
    params[:identity]&.[](:primary_email)&.downcase!

    existing_identity = Identity.find_by(primary_email: params.dig(:identity, :primary_email))
    if existing_identity
      session[:sign_in_email] = existing_identity.primary_email
      flash[:warning] = "An account with this email already exists. <a href='#{signin_onboarding_path}'>Sign in here</a> if it's yours.".html_safe
      @identity = Identity.new(basic_info_params)
      render :basic_info, status: :unprocessable_entity
      return
    end

    @identity = Identity.new(basic_info_params)

    if @identity.save
      session[:identity_id] = @identity.id
      redirect_to_current_step
    else
      render :basic_info, status: :unprocessable_entity
    end
  end

  def document
    if @identity.verification_status == "ineligible"
      redirect_to submitted_onboarding_path and return
    end

    @document = @identity.documents.build
    @is_resubmission = resubmission_scenario?
    @rejected_verifications = rejected_verifications_for_resubmission if @is_resubmission
  end

  def create_document
    return redirect_to_basic_info_onboarding_path unless @identity

    if @identity.verification_status == "ineligible"
      redirect_to submitted_onboarding_path and return
    end

    @document = @identity.documents.build(document_params)

    if create_document_and_verification
      VerificationMailer.created(@verification).deliver_later
      Identity::NoticeResemblancesJob.perform_later(@identity)
      redirect_to_current_step
    else
      @is_resubmission = resubmission_scenario?
      @rejected_verifications = rejected_verifications_for_resubmission if @is_resubmission
      set_default_document_type
      render :document, status: :unprocessable_entity
    end
  end

  def aadhaar
    if @identity.verification_status == "ineligible"
      redirect_to submitted_onboarding_path and return
    end
  end

  def submit_aadhaar
    if @identity.verification_status == "ineligible"
      redirect_to submitted_onboarding_path and return
    end

    if aadhaar_params[:aadhaar_number].present? && Identity.where(aadhaar_number: aadhaar_params[:aadhaar_number]).where.not(id: current_identity.id).exists?
      flash[:warning] = "An account with this Aadhaar number already exists. <a href='#{signin_onboarding_path}'>Sign in here</a> if it's yours.".html_safe
      render :aadhaar, status: :unprocessable_entity
      return
    end

    Rails.logger.info "Updating identity with Aadhaar number: #{aadhaar_params.inspect}"

    begin
      @identity.update!(aadhaar_params)
      @aadhaar_verification = @identity.aadhaar_verifications.create!
      redirect_to_current_step
    rescue StandardError => e
      uuid = Honeybadger.notify(e)
      Rails.logger.error "Aadhaar update failed with errors: #{e.message} (report error ID: #{uuid})"
      render :aadhaar, status: :unprocessable_entity
    end
  end

  def aadhaar_step_2
    if @identity.verification_status == "ineligible"
      redirect_to submitted_onboarding_path and return
    end

    @verification = @identity.aadhaar_verifications.draft.first
  end

  def address
    @address = @identity.addresses.build
    @address.first_name = @identity.first_name
    @address.last_name = @identity.last_name
    @address.country = @identity.country
  end

  def create_address
    return redirect_to_basic_info_onboarding_path unless @identity

    @address = @identity.addresses.build(address_params)

    if @address.save
      if @identity.primary_address.nil?
        @identity.update!(primary_address: @address)
      end
      redirect_to_current_step
    else
      render :address, status: :unprocessable_entity
    end
  end

  def submitted
    if session[:oauth_return_to]
      redirect_to continue_onboarding_path
      return
    end

    @documents = @identity.documents.includes(:verifications)
  end

  def continue
    return_path = session[:oauth_return_to] || root_path
    session[:oauth_return_to] = nil
    redirect_to return_path, allow_other_host: true
  end

  private

  def set_identity
    @identity = current_identity
    redirect_to basic_info_onboarding_path unless @identity&.persisted?
  end

  def ensure_correct_step
    correct_step_path = determine_current_step

    return if request.path == correct_step_path

    Rails.logger.info "Onboarding step redirect: #{request.path} -> #{correct_step_path}"
    redirect_to correct_step_path
  end

  def redirect_to_current_step
    redirect_to determine_current_step
  end

  def ensure_aadhaar_makes_sense
    redirect_to_current_step unless Flipper.enabled?(:integrated_aadhaar_2025_07_10, @identity) && @identity&.country == "IN"
  end

  # disgusting disgusting disgusting
  def determine_current_step
    identity = current_identity

    unless identity&.persisted?
      return basic_info_onboarding_path if request.path == basic_info_onboarding_path
      return welcome_onboarding_path
    end

    identity.onboarding_redirect_path
  rescue StandardError => e
    Rails.logger.error "Onboarding step determination failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    welcome_onboarding_path
  end

  def resubmission_scenario? = @identity.in_resubmission_flow?

  def rejected_verifications_for_resubmission = @identity.rejected_verifications_for_context

  def create_document_and_verification
    return false unless @document.save

    @verification = @identity.document_verifications.build(
      identity_document: @document,
    )

    unless @verification.save
      Rails.logger.error "Verification creation failed: #{@verification.errors.full_messages}"
      @document.errors.add(:base, "Unable to create verification: #{@verification.errors.full_messages.join(", ")}")
      return false
    end

    true
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "Document creation failed: #{e.message}"
    @document.errors.add(:base, "Unable to save document: #{e.message}")
    false
  rescue StandardError => e
    Rails.logger.error "Unexpected error creating document: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    Honeybadger.notify(e)
    @document.errors.add(:base, "An unexpected error occurred. Please try again.")
    false
  end

  def set_default_document_type
    return if @document.document_type.present?

    @document.document_type = Identity::Document.selectable_types_for_country(@identity.country)&.first
  end

  def basic_info_params
    params.require(:identity).permit(
      :first_name, :last_name, :legal_first_name, :legal_last_name,
      :country, :primary_email, :slack_id, :birthday, :phone_number
    )
  end

  def document_params = params.require(:identity_document).permit(:document_type, files: [])

  def aadhaar_params = params.require(:identity).permit(:aadhaar_number)

  def address_params = params.require(:address).permit(:first_name, :last_name, :line_1, :line_2, :city, :state, :postal_code, :country)
end
