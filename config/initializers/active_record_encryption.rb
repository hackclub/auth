# frozen_string_literal: true

# Configure Active Record Encryption to use environment variables
# instead of Rails credentials

if ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"].present?
  config = {
    primary_key: ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"],
    deterministic_key: ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"],
    key_derivation_salt: ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"]
  }

  config.each do |key, value|
    Rails.application.config.active_record.encryption.send(:"#{key}=", value)
    ActiveRecord::Encryption.config.send(:"#{key}=", value)
  end
end
