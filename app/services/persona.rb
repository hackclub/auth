module Persona
  Inquiry = Data.define(:id, :status, :account_id, :session_token, :verification_ids, :document_ids, :behaviors, :sessions, :raw) do
    def gov_id_verification_id
      verification_ids&.find { |v| v[:type] == "verification/government-id" }&.dig(:id)
    end

    def gov_id_document_id
      document_ids&.find { |d| d[:type] == "document/government-id" }&.dig(:id)
    end

    def selfie_verification_id
      verification_ids&.find { |v| v[:type] == "verification/selfie" }&.dig(:id)
    end
  end

  GovernmentIdVerification = Data.define(
    :id, :status, :name_first, :name_last, :birthdate,
    :country_code, :id_class, :expiration_date,
    :entity_confidence_score, :checks,
    :front_photo, :back_photo, :selfie_photo,
    :raw
  )

  PhotoSet = Data.define(:document, :liveness) do
    def self.empty = new(document: [], liveness: [])

    def +(other)
      PhotoSet.new(
        document:  document + other.document,
        liveness:  liveness + other.liveness
      )
    end
  end

  APIError = Class.new(StandardError)
  ConflictError = Class.new(APIError)

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
