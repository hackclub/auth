module Persona
  Inquiry = Data.define(:id, :status, :account_id, :session_token, :verification_ids) do
    def gov_id_verification_id
      verification_ids&.find { |v| v[:type] == "verification/government-id" }&.dig(:id)
    end
  end

  GovernmentIdVerification = Data.define(
    :id, :status, :name_first, :name_last, :birthdate,
    :country_code, :front_photo, :back_photo, :selfie_photo,
    :id_class, :expiration_date, :entity_confidence_score, :checks
  )

  APIError = Class.new(StandardError)

  class << self
    def instance
      @instance ||= if Rails.env.test?
        MockAPIService.new
      elsif (creds = Rails.application.credentials.persona)&.api_key
        APIService.new(api_key: creds.api_key)
      else
        raise APIError, "persona credentials not configured — add persona.api_key to Rails credentials"
      end
    end

    def reset! = @instance = nil
  end
end
