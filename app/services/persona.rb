module Persona
  Inquiry = Data.define(:id, :status, :account_id, :session_token, :verification_ids) do
    def gov_id_verification_id
      verification_ids&.find { |v| v[:type] == "verification/government-id" }&.dig(:id)
    end
  end

  GovernmentIdVerification = Data.define(
    :id, :status, :name_first, :name_last, :birthdate,
    :country_code, :front_photo, :back_photo, :selfie_photo
  )

  APIError = Class.new(StandardError)

  class << self
    def instance
      @instance ||= Rails.env.production? ?
        APIService.new(api_key: Rails.application.credentials.persona.api_key) :
        MockAPIService.new
    end

    def reset! = @instance = nil
  end
end
