# Configure WebAuthn for passkey authentication
WebAuthn.configure do |config|
  # The allowed origins - where WebAuthn requests can come from
  config.allowed_origins = if Rails.env.production?
    ["https://account.hackclub.com"]
  elsif Rails.env.development?
    ["http://localhost:3000"]
  else
    # For test environment or other environments
    ["http://localhost:3000"]
  end

  # The Relying Party name - shown in authenticator UI
  config.rp_name = "Hack Club Account"

  # Credential options (optional - these are the defaults)
  # Algorithms we support for credential public keys
  # ES256 is ECDSA with SHA-256, the most widely supported algorithm
  # RS256 is RSA with SHA-256, supported by some older authenticators
  config.algorithms = ["ES256", "RS256"]
end
