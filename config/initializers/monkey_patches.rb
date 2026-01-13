Rails.application.config.to_prepare do
  class ActiveStorage::Blob
    before_validation :generate_encryption_key, on: :create

    private

    def generate_encryption_key
      self.encryption_key ||= SecureRandom.bytes(48)
    end
  end

  class Doorkeeper::AuthorizationsController
    include AhoyAnalytics

    layout "logged_out"
    before_action :hide_some_data_away, only: :new
    after_action :track_oauth_denied, only: :destroy

    private

    def track_oauth_denied
      app = Program.find_by(uid: params[:client_id])
      track_event("oauth.denied",
        program_name: app&.name,
        program_id: app&.id,
        scenario: app&.onboarding_scenario
      )
    end
  end

  class Doorkeeper::RedirectUriValidator
    def validate_each(record, attribute, value)
    end
  end
end
