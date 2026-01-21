# frozen_string_literal: true

# Seeds for local development
# Run with: bin/rails db:seed

return unless Rails.env.development?

puts "🌱 seeding development data..."

# Create a test identity
identity = Identity.find_or_initialize_by(primary_email: "identity@hackclub.com")

if identity.new_record?
  identity.assign_attributes(
    first_name: "Dev",
    last_name: "User",
    birthday: Date.new(2000, 1, 1),
    country: :US
  )
  identity.save!
  puts "  created identity: #{identity.primary_email}"
else
  puts "  identity already exists: #{identity.primary_email}"
end

# Create or find a verified TOTP for backend access
totp = identity.totps.verified.first || identity.totps.find_by(aasm_state: "unverified")

if totp.nil?
  totp = identity.totps.create!(aasm_state: "verified")
  puts "  created TOTP for 2FA"
elsif totp.aasm_state != "verified"
  totp.update!(aasm_state: "verified")
  puts "  verified existing TOTP"
else
  puts "  TOTP already exists and verified"
end

# Create backend user with super admin
backend_user = identity.backend_user || identity.build_backend_user

if backend_user.new_record?
  backend_user.assign_attributes(
    username: "dev",
    active: true,
    super_admin: true
  )
  backend_user.save!
  puts "  created backend user with super_admin"
else
  puts "  backend user already exists"
end

puts ""
puts "=" * 60
puts "dev account ready!"
puts "=" * 60
puts ""
puts "  email: identity@hackclub.com"
puts "  totp secret: #{totp.secret}"
puts ""
puts "add this secret to your authenticator app, or use this URI:"
puts ""
puts "  #{totp.provisioning_uri}"
puts ""
puts "login flow:"
puts "  1. go to http://localhost:3000/login"
puts "  2. enter: identity@hackclub.com"
puts "  3. grab the code from http://localhost:3000/letter_opener"
puts "  4. enter the TOTP code from your authenticator"
puts "  5. go to http://localhost:3000/backend"
puts ""
puts "=" * 60
