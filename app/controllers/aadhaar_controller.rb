# frozen_string_literal: true

class AadhaarController < ApplicationController
  before_action :ensure_step, :set_verification
  layout false

  def async_digilocker_link
    begin
      @verification.generate_link!(
        callback_url: webhooks_aadhaar_callback_url(
          Rails.application.credentials.dig(:aadhaar, :webhook_secret)
        ),
        redirect_url: submitted_onboarding_url,
      ) unless @verification.aadhaar_external_transaction_id.present?

      render :digilocker_link
    rescue StandardError => e
      uuid = Honeybadger.notify(e)
      response.set_header("HX-Retarget", "#async_flash")
      render "shared/async_flash", locals: { f: { error: "error generating digilocker link – #{e.message} #{uuid}" } }
    end
  end

  def digilocker_redirect
    redirect_to @verification.aadhaar_link, allow_other_host: true
  end

  private

  def set_verification
    @verification = current_identity.aadhaar_verifications.draft.first
  end

  def ensure_step
    render html: "🥐" unless current_identity&.onboarding_step == :aadhaar

    if current_identity&.verification_status == "ineligible"
      redirect_to submitted_onboarding_path and return
    end
  end
end
