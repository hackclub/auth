Rails.application.config.to_prepare do
  class ActiveStorage::Blob
    before_validation :generate_encryption_key, on: :create

    private

    def generate_encryption_key
      self.encryption_key ||= SecureRandom.bytes(48)
    end
  end

  class Doorkeeper::AuthorizationsController
    before_action :hide_some_data_away, only: :new
  end

  class Doorkeeper::RedirectUriValidator
    def validate_each(record, attribute, value)
    end
  end
end
