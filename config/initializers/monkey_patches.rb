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

  # Fix public_activity 3.0.2 crash when `parameters` column contains
  # raw strings instead of YAML-deserialized hashes.
  PublicActivity::Activity.prepend(Module.new do
    def prepare_parameters(params)
      p = self.parameters
      if p.is_a?(String)
        p = (YAML.safe_load(p, permitted_classes: [Symbol]) rescue {}) || {}
      end
      if p.is_a?(Hash)
        @prepared_params ||= p.with_indifferent_access.merge(params)
      else
        @prepared_params ||= params
      end
    end
  end)
end
