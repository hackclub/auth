module Persona
  Inquiry = Data.define(:id, :status, :account_id, :session_token)

  GovernmentIdVerification = Data.define(
    :id, :status,
    :name_first, :name_last, :birthdate, :country_code,
    :front_photo, :back_photo, :selfie_photo
  )

  APIError = Class.new(StandardError)

  class << self
    def instance
      @instance ||= if Rails.env.production?
        Persona::APIService.new(api_key: Rails.application.credentials.persona.api_key)
      else
        Persona::MockAPIService.new
      end
    end

    def reset!
      @instance = nil
    end
  end
end
