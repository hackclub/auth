require "rails_helper"

RSpec.describe PendingAuthorization, type: :model do
  let(:browser_session) { create(:browser_session) }

  describe ".park!" do
    it "stores the request encrypted, behind an opaque handle" do
      pending = described_class.park!(
        browser_session: browser_session,
        kind: "oidc",
        payload: { "params" => { "login_hint" => "nora@hackclub.com" } }
      )

      raw = ActiveRecord::Base.connection.select_value(
        "SELECT payload_ciphertext FROM pending_authorizations WHERE id = #{pending.id}"
      )
      expect(raw).not_to include("nora@hackclub.com")
      expect(pending.reload.payload.dig("params", "login_hint")).to eq("nora@hackclub.com")
      expect(pending.token).to be_present
    end
  end

  describe ".consume!" do
    let!(:pending) { described_class.park!(browser_session: browser_session, kind: "oidc", payload: { "params" => {} }) }

    it "returns the record and marks it used" do
      consumed = described_class.consume!(token: pending.token, browser_session: browser_session)

      expect(consumed).to eq(pending)
      expect(pending.reload).to be_consumed
    end

    it "refuses a second use" do
      described_class.consume!(token: pending.token, browser_session: browser_session)

      expect(described_class.consume!(token: pending.token, browser_session: browser_session)).to be_nil
    end

    it "refuses a different browser session" do
      other = create(:browser_session)

      expect(described_class.consume!(token: pending.token, browser_session: other)).to be_nil
      expect(pending.reload).not_to be_consumed
    end

    it "refuses an expired handle" do
      pending.update!(expires_at: 1.minute.ago)

      expect(described_class.consume!(token: pending.token, browser_session: browser_session)).to be_nil
    end

    it "refuses a kind mismatch" do
      expect(described_class.consume!(token: pending.token, browser_session: browser_session, kind: "saml")).to be_nil
    end

    it "refuses a blank or unknown token" do
      expect(described_class.consume!(token: nil, browser_session: browser_session)).to be_nil
      expect(described_class.consume!(token: "nope", browser_session: browser_session)).to be_nil
    end
  end
end
