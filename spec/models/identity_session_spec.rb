require "rails_helper"

RSpec.describe IdentitySession, type: :model do
  let(:identity) { create(:identity) }
  let(:identity_session) do
    identity.sessions.create!(
      session_token: SecureRandom.hex(32),
      expires_at: 1.week.from_now
    )
  end

  describe "#recently_authenticated?" do
    it "is true for a session created within the step-up window" do
      expect(identity_session.recently_authenticated?).to be true
    end

    it "is false for a session older than the step-up window" do
      identity_session.update_column(:created_at, IdentitySession::STEP_UP_DURATION.ago - 1.minute)

      expect(identity_session.recently_authenticated?).to be false
    end
  end
end
