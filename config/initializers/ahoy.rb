# frozen_string_literal: true

class Ahoy::Store < Ahoy::DatabaseStore
end

Ahoy.api = false # Server-side only, no JavaScript tracking
Ahoy.cookies = true # Cookie-based visitor tracking
Ahoy.cookie_options = {
  same_site: :lax,
  secure: Rails.env.production? || Rails.env.staging?
}

# Privacy settings
Ahoy.mask_ips = true # Mask IPs for privacy (192.168.1.x -> 192.168.1.0)
Ahoy.geocode = false # Don't geocode IPs
Ahoy.track_bots = false # Exclude bot traffic

# Visit duration for grouping events
Ahoy.visit_duration = 4.hours

# Server-side visits
Ahoy.server_side_visits = :when_needed

# IMPORTANT: Do not associate visits/events with users
# We explicitly don't set Ahoy.user_method to keep analytics anonymous
