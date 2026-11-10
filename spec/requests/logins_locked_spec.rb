# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Logging in to a locked account", type: :request do
  let(:identity) { create(:identity) }

  it "finishing with TOTP redirects back to login with the lock message" do
    totp = identity.totps.create!(aasm_state: "verified")
    identity.update!(use_two_factor_authentication: true)
    attempt = LoginAttempt.create!(identity:, authentication_factors: { email: true }, provenance: "login")
    identity.update!(locked_at: Time.current)

    post verify_totp_login_attempt_path(id: attempt.to_param),
      params: { code: ROTP::TOTP.new(totp.secret).now }

    expect(response).to redirect_to(login_path)
    expect(flash[:error]).to eq("Your account has been locked.")
  end
end
