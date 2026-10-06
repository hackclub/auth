# frozen_string_literal: true

keys = {
  primary_key: ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"],
  deterministic_key: ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"],
  key_derivation_salt: ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"]
}

unless keys.values.all?(&:present?)
  unless Rails.env.local?
    raise "ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY, DETERMINISTIC_KEY, and KEY_DERIVATION_SALT are required"
  end

  keys = {
    primary_key: Digest::SHA256.hexdigest("hca-ar-encryption-primary"),
    deterministic_key: Digest::SHA256.hexdigest("hca-ar-encryption-deterministic"),
    key_derivation_salt: Digest::SHA256.hexdigest("hca-ar-encryption-salt")
  }
end

keys.each do |name, value|
  Rails.application.config.active_record.encryption.public_send(:"#{name}=", value)
  ActiveRecord::Encryption.config.public_send(:"#{name}=", value)
end
