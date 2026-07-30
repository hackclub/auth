require "rails_helper"

RSpec.describe IdentitySession, type: :model do
  let(:identity) { create(:identity) }
  let(:ident_session) { create(:identity_session, identity: identity) }

  def record_factors(factors)
    LoginAttempt.create!(
      identity: identity,
      session: ident_session,
      authentication_factors: factors,
      aasm_state: "complete",
      provenance: "login",
      next_action: "home"
    )
    ident_session.reload
  end

  describe "#amr_values" do
    it "is nil when there is no login attempt to derive from" do
      expect(ident_session.amr_values).to be_nil
      expect(ident_session.acr_value).to be_nil
    end

    it "reports a single factor without mfa" do
      record_factors("email" => true)

      expect(ident_session.amr_values).to eq([ "otp" ])
      expect(ident_session.acr_value).to eq(described_class::ACR_SINGLE_FACTOR)
    end

    it "adds mfa once two factors are satisfied" do
      record_factors("email" => true, "totp" => true)

      expect(ident_session.amr_values).to include("mfa")
      expect(ident_session.acr_value).to eq(described_class::ACR_MULTI_FACTOR)
    end

    it "maps passkeys to hwk" do
      record_factors("webauthn" => true)

      expect(ident_session.amr_values).to eq([ "hwk" ])
    end

    it "ignores factors recorded as false" do
      record_factors("email" => true, "totp" => false)

      expect(ident_session.amr_values).to eq([ "otp" ])
      expect(ident_session).not_to be_multi_factor
    end
  end

  describe "#revoke!" do
    it "expires the session and records why" do
      ident_session.revoke!(reason: "user_signout")

      expect(ident_session).to be_expired
      expect(ident_session.signed_out_at).to be_present
      expect(ident_session.revoked_reason).to eq("user_signout")
      expect(ident_session).not_to be_live
    end
  end
end
