# frozen_string_literal: true

# Configure Active Record Encryption to use environment variables
# instead of Rails credentials

if ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"].present?
  Rails.application.config.active_record.encryption.primary_key = ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"]
  Rails.application.config.active_record.encryption.deterministic_key = ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"]
  Rails.application.config.active_record.encryption.key_derivation_salt = ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"]

  # setting app config alone is not enough when ActiveRecord has already
  # been loaded by an earlier railtie — the framework copies these values
  # exactly once, on AR load. configure directly so the keys always land.
  ActiveSupport.on_load(:active_record) do
    ActiveRecord::Encryption.configure(
      primary_key: ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"],
      deterministic_key: ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"],
      key_derivation_salt: ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"]
    )
  end
end
