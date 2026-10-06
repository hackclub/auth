require "rails_helper"

RSpec.describe "Passkey prompt routing", type: :request do
  let(:identity) { create(:identity) }

  def login_with_code(return_to: nil)
    attempt = LoginAttempt.create!(
      identity: identity,
      authentication_factors: {},
      provenance: "login",
      next_action: "home",
      return_to: return_to
    )
    code = Identity::V2LoginCode.generate(identity)
    post verify_login_attempt_path(attempt.to_param), params: { code: code.code }
  end

  it "routes an eligible identity through the passkey setup step" do
    login_with_code

    expect(response).to redirect_to(passkey_setup_path(return_to: "/"))
  end

  it "preserves the return_to (e.g. OAuth) through the setup step" do
    login_with_code(return_to: "/oauth/authorize?client_id=test")

    expect(response).to redirect_to(passkey_setup_path(return_to: "/oauth/authorize?client_id=test"))
  end

  it "sends a passkey holder straight to the destination" do
    identity.webauthn_credentials.create!(
      webauthn_id: SecureRandom.random_bytes(32),
      webauthn_public_key: SecureRandom.random_bytes(65)
    )

    login_with_code

    expect(response).to redirect_to("/")
  end

  it "sends a dismissed identity straight to the destination" do
    identity.dismiss_passkey_promotion!

    login_with_code

    expect(response).to redirect_to("/")
  end
end
