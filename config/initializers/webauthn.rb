# Configure WebAuthn for passkey authentication
WebAuthn.configure do |config|
  # The allowed origins - where WebAuthn requests can come from
  config.allowed_origins = if Rails.env.production?
    [ "https://auth.hackclub.com" ]
  elsif Rails.env.development?
    [ "http://localhost:3000" ]
  elsif ENV["APP_HOST"].present?
    [ "https://#{ENV["APP_HOST"]}" ]
  else
    [ "http://localhost:3000" ]
  end

  config.rp_name = "Hack Club Auth"

  config.rp_id = if Rails.env.production?
    "auth.hackclub.com"
  elsif ENV["APP_HOST"].present?
    ENV["APP_HOST"]
  else
    "localhost"
  end

  # Credential options (optional - these are the defaults)
  # Algorithms we support for credential public keys
  # ES256 is ECDSA with SHA-256, the most widely supported algorithm
  # RS256 is RSA with SHA-256, supported by some older authenticators
  config.algorithms = [ "ES256", "RS256" ]
end
