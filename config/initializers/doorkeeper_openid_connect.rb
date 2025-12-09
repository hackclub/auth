# frozen_string_literal: true

Doorkeeper::OpenidConnect.configure do
  issuer do |_resource_owner, _application|
    if Rails.env.production?
      "https://auth.hackclub.com"
    elsif Rails.env.staging? || Rails.env.uat?
      "https://hca.dinosaurbbq.org"
    else
      "http://localhost:3000"
    end
  end

  signing_key ENV["OIDC_SIGNING_KEY"]

  protocol do
    Rails.env.development? ? :http : :https
  end

  signing_algorithm :rs256

  subject_types_supported [ :public ]

  resource_owner_from_access_token do |access_token|
    Identity.find_by(id: access_token.resource_owner_id)
  end

  auth_time_from_resource_owner do |resource_owner|
    session = resource_owner.sessions.not_expired.order(created_at: :desc).first
    return nil unless session

    [ session.created_at, session.last_step_up_at ].compact.max
  end

  reauthenticate_resource_owner do |resource_owner, return_to|
    session = resource_owner.sessions.not_expired.order(created_at: :desc).first
    return if session&.last_step_up_at&.after?(60.seconds.ago)

    redirect_to new_step_up_path(action_type: "oidc_reauth", return_to: return_to)
  end

  subject { |ident, _application| ident.public_id }

  claims do
    # standard scopes:
    normal_claim(:email, scope: :email) { |ident| ident.primary_email }
    normal_claim(:email_verified, scope: :email) { |_ident| true }

    normal_claim(:phone_number, scope: :phone) { |ident| ident.phone_number }
    normal_claim(:phone_number_verified, scope: :phone) { |_ident| false } # TODO: eventually we'll have phone number verification

    normal_claim(:name, scope: :profile) { |ident| "#{ident.first_name} #{ident.last_name}" }
    normal_claim(:given_name, scope: :profile) { |ident| ident.first_name }
    normal_claim(:family_name, scope: :profile) { |ident| ident.last_name }
    normal_claim(:nickname, scope: :profile) { |ident| ident.first_name } # TODO: display names...
    normal_claim(:updated_at, scope: :profile) { |ident| ident.updated_at.to_i }

    # birthdate scope (separate from profile for privacy)
    normal_claim(:birthdate, scope: :birthdate) { |ident| ident.birthday&.to_s }

    # addresses.... it's always addresses
    normal_claim :address, scope: :address do |resource_owner|
      addr = resource_owner.primary_address
      next nil unless addr

      {
        street_address: [ addr.line_1, addr.line_2 ].compact.join("\n"),
        locality: addr.city,
        region: addr.state,
        postal_code: addr.postal_code,
        country: addr.country.to_s
      }.compact
    end

    # HCA-custom claims:
    normal_claim(:slack_id, scope: :slack_id) { |ident| ident.slack_id }
    normal_claim(:verification_status, scope: :verification_status) { |ident| ident.verification_status }
    normal_claim(:ysws_eligible, scope: :verification_status) { |ident| ident.ysws_eligible }
  end
end
