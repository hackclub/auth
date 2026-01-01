class EmailChangesController < ApplicationController
  skip_before_action :authenticate_identity!, only: [ :verify_old, :verify_new, :confirm_verify_old, :confirm_verify_new ]

  before_action :set_email_change_request, only: [ :show, :cancel_confirmation, :cancel ]
  before_action :require_step_up_for_email_change, only: [ :new, :create ]

  def new
    pending_request = current_identity.email_change_requests.pending.first
    if pending_request
      redirect_to email_change_path(pending_request), notice: t(".pending_redirect")
      return
    end

    @email_change_request = Identity::EmailChangeRequest.new
  end

  def show
  end

  def create
    new_email = email_change_params[:new_email]&.downcase&.strip

    if new_email.blank?
      flash[:error] = t(".email_required")
      return redirect_to new_email_change_path
    end

    existing_pending = current_identity.email_change_requests.pending.first
    if existing_pending
      existing_pending.cancel!
    end

    @email_change_request = current_identity.email_change_requests.build(
      new_email: new_email,
      old_email: current_identity.primary_email,
      requested_from_ip: request.remote_ip
    )

    if @email_change_request.save
      @email_change_request.generate_tokens!
      @email_change_request.send_verification_emails!
      consume_step_up!
      flash[:success] = t(".success")
      redirect_to email_change_path(@email_change_request)
    else
      flash[:error] = @email_change_request.errors.full_messages.to_sentence
      redirect_to new_email_change_path
    end
  end

  def verify_old
    @email_change_request = Identity::EmailChangeRequest.pending.find_by!(old_email_token: params[:token])
    @token = params[:token]
  rescue ActiveRecord::RecordNotFound
    flash[:error] = t(".invalid_or_expired")
    redirect_to root_path
  end

  def confirm_verify_old
    @email_change_request = Identity::EmailChangeRequest.pending.find_by!(old_email_token: params[:token])

    if @email_change_request.verify_old_email!(params[:token])
      flash[:success] = t("email_changes.verify_old.success")
      if @email_change_request.completed?
        flash[:success] = t("email_changes.verify_old.email_changed")
      end
    else
      flash[:error] = t("email_changes.verify_old.invalid_or_expired")
    end

    if identity_signed_in?
      redirect_to email_change_path(@email_change_request)
    else
      redirect_to login_path
    end
  rescue ActiveRecord::RecordNotFound
    flash[:error] = t("email_changes.verify_old.invalid_or_expired")
    redirect_to root_path
  end

  def verify_new
    @email_change_request = Identity::EmailChangeRequest.pending.find_by!(new_email_token: params[:token])
    @token = params[:token]
  rescue ActiveRecord::RecordNotFound
    flash[:error] = t(".invalid_or_expired")
    redirect_to root_path
  end

  def confirm_verify_new
    @email_change_request = Identity::EmailChangeRequest.pending.find_by!(new_email_token: params[:token])

    if @email_change_request.verify_new_email!(params[:token])
      flash[:success] = t("email_changes.verify_new.success")
      if @email_change_request.completed?
        flash[:success] = t("email_changes.verify_new.email_changed")
      end
    else
      flash[:error] = t("email_changes.verify_new.invalid_or_expired")
    end

    if identity_signed_in?
      redirect_to email_change_path(@email_change_request)
    else
      redirect_to login_path
    end
  rescue ActiveRecord::RecordNotFound
    flash[:error] = t("email_changes.verify_new.invalid_or_expired")
    redirect_to root_path
  end

  def cancel_confirmation
  end

  def cancel
    if @email_change_request.cancel!
      flash[:success] = t(".success")
    else
      flash[:error] = t(".already_completed")
    end

    redirect_to edit_identity_path
  end

  private

  def set_email_change_request
    @email_change_request = current_identity.email_change_requests.find_by_public_id!(params[:id])
  end

  def email_change_params
    params.require(:email_change).permit(:new_email)
  end

  def require_step_up_for_email_change
    require_step_up("email_change", return_to: new_email_change_path)
  end
end
