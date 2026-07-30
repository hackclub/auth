require "rails_helper"

RSpec.describe IdTokenHintVerifier, type: :model do
  let(:identity) { create(:identity) }
  let(:program) { create(:program, scopes: "openid email") }

  before do
    unless ENV["OIDC_SIGNING_KEY"].present?
      Doorkeeper::OpenidConnect.configuration
        .instance_variable_set(:@signing_key, OpenSSL::PKey::RSA.generate(2048).to_pem)
    end
  end

  def issued_token(expires_in: 120)
    token = create(:oauth_token, resource_owner: identity, application: program, scopes: "openid email")
    Doorkeeper::OpenidConnect::IdToken.new(token, "nonce", expires_in).as_jws_token
  end

  it "returns no subject and no error for a blank hint" do
    result = described_class.call(nil)

    expect(result).not_to be_present
    expect(result).not_to be_invalid
  end

  it "extracts the subject from a token we issued" do
    result = described_class.call(issued_token, audience: program.uid)

    expect(result.subject).to eq(identity.public_id)
    expect(result).not_to be_invalid
  end

  # OIDC Core requires that an expired ID token still work as a hint — it is
  # telling us who the user was last time, not authorising anything.
  it "accepts an expired token" do
    hint = issued_token(expires_in: -3600)

    expect(described_class.call(hint, audience: program.uid).subject).to eq(identity.public_id)
  end

  it "rejects a token for a different client" do
    result = described_class.call(issued_token, audience: "someone-elses-client-id")

    expect(result).to be_invalid
  end

  it "rejects a token signed by someone else" do
    foreign = JWT.encode(
      { "iss" => "http://localhost:3000", "sub" => identity.public_id, "aud" => program.uid },
      OpenSSL::PKey::RSA.generate(2048),
      "RS256"
    )

    expect(described_class.call(foreign, audience: program.uid)).to be_invalid
  end

  it "rejects garbage" do
    expect(described_class.call("not.a.jwt")).to be_invalid
  end
end
