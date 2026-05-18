# frozen_string_literal: true

if ENV["LOCKBOX_MASTER_KEY"].present?
  Lockbox.master_key = ENV["LOCKBOX_MASTER_KEY"]
elsif Rails.env.development? || Rails.env.test?
  # generate a deterministic key for dev/test so encrypted data persists across restarts
  # this is NOT secure for production – always set LOCKBOX_MASTER_KEY in prod
  Lockbox.master_key = Digest::SHA256.hexdigest("hca-dev-key")
elsif ENV["SECRET_KEY_BASE_DUMMY"].present?
  # allow Rails to boot during asset precompilation without real secrets
  Lockbox.master_key = "0" * 64
else
  raise "LOCKBOX_MASTER_KEY must be set in production"
end
