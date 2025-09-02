module AadhaarService
  class << self
    def instance
      @instance ||= (Rails.env.production? ? AadhaarService::Production : AadhaarService::Mock).new
    end
  end
end
