require "rails_helper"

RSpec.describe "Disabling 2FA when required by admin", type: :request do
  let(:identity) { create(:identity, two_factor_required: true, use_two_factor_authentication: true) }
  let(:session) do
    identity.sessions.create!(
      session_token: SecureRandom.hex(32),
      expires_at: 1.week.from_now
    )
  end
  let!(:totp) do
    t = identity.totps.create!
    t.mark_verified!
    t
  end

  before do
    allow_any_instance_of(ApplicationController).to receive(:current_identity).and_return(identity)
    allow_any_instance_of(ApplicationController).to receive(:current_session).and_return(session)
    allow_any_instance_of(ApplicationController).to receive(:identity_signed_in?).and_return(true)
  end

  describe "POST /identity/toggle_2fa" do
    it "refuses to start the disable flow" do
      post toggle_2fa_identity_path

      expect(response).to redirect_to(security_path)
      expect(flash[:error]).to include("can't be disabled")
      expect(identity.reload.use_two_factor_authentication).to be true
    end
  end

  describe "step-up disable_2fa completion" do
    it "refuses to disable the 2FA requirement" do
      code = ROTP::TOTP.new(totp.secret).now

      post "/step_up/verify", params: { action_type: "disable_2fa", method: "totp", code: code }

      expect(response).to redirect_to(security_path)
      expect(flash[:alert]).to include("can't be disabled")
      expect(identity.reload.use_two_factor_authentication).to be true
    end
  end

  describe "step-up remove_totp completion" do
    it "refuses to remove the last 2FA method" do
      code = ROTP::TOTP.new(totp.secret).now

      post "/step_up/verify", params: { action_type: "remove_totp", method: "totp", code: code }

      expect(response).to redirect_to(security_path)
      expect(flash[:alert]).to include("Add another method")
      expect(identity.reload.totp).to be_present
    end

    it "allows removing the TOTP when a passkey remains" do
      identity.webauthn_credentials.create!(
        external_id: SecureRandom.hex(16),
        public_key: SecureRandom.hex(32),
        nickname: "test key",
        sign_count: 0
      )
      code = ROTP::TOTP.new(totp.secret).now

      post "/step_up/verify", params: { action_type: "remove_totp", method: "totp", code: code }

      expect(response).to redirect_to(security_path)
      expect(identity.reload.totp).to be_nil
    end
  end
end
