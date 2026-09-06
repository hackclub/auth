# frozen_string_literal: true

# Configure Active Record Encryption to use environment variables
# instead of Rails credentials

config = {
  primary_key: ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"],
  deterministic_key: ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"],
  key_derivation_salt: ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"]
}

if config.values.all?(&:present?)
  # use env
elsif Rails.env.development? || Rails.env.test?
  # deterministic keys so encrypted data persists across restarts.
  # NOT secure for production — always set the ENV vars in prod.
  config = {
    primary_key: Digest::SHA256.hexdigest("hca-ar-encryption-primary"),
    deterministic_key: Digest::SHA256.hexdigest("hca-ar-encryption-deterministic"),
    key_derivation_salt: Digest::SHA256.hexdigest("hca-ar-encryption-salt")
  }
elsif ENV["SECRET_KEY_BASE_DUMMY"].present?
  # allow Rails to boot during asset precompilation without real secrets
  config = {
    primary_key: "0" * 64,
    deterministic_key: "1" * 64,
    key_derivation_salt: "2" * 64
  }
else
  config = nil
end

if config
  config.each do |key, value|
    Rails.application.config.active_record.encryption.send(:"#{key}=", value)
    ActiveRecord::Encryption.config.send(:"#{key}=", value)
  end
end
