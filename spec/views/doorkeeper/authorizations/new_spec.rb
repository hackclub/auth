require "rails_helper"

RSpec.describe "doorkeeper/authorizations/new", type: :view do
  let(:address) { build_stubbed(:address, line_1: "123 Main St", city: "Burlington", state: "VT", country: "US") }
  let(:identity) do
    build_stubbed(:identity).tap { |i| allow(i).to receive(:primary_address).and_return(address) }
  end
  let(:program) { build_stubbed(:program, name: "Test App") }
  let(:scopes) { Doorkeeper::OAuth::Scopes.from_string("openid email") }
  let(:pre_auth) do
    double(
      "PreAuth",
      client: double("Client", uid: program.uid, name: program.name),
      scopes: scopes,
      scope: scopes.to_s,
      redirect_uri: "https://example.com/callback",
      state: "abc123",
      response_type: "code",
      response_mode: nil,
      nonce: nil,
      code_challenge: nil,
      code_challenge_method: nil
    )
  end

  before do
    assign(:pre_auth, pre_auth)
    allow(view).to receive(:current_identity).and_return(identity)
    allow(view).to receive(:session).and_return({ stashed_data: nil })
    allow(Program).to receive(:find_by).and_return(program)
    allow(view).to receive(:oauth_authorization_path).and_return("/oauth/authorize")
  end

  describe "scope display" do
    it "shows email for email scope" do
      render
      expect(rendered).to include(identity.primary_email)
    end

    it "shows name for name scope" do
      allow(pre_auth).to receive(:scopes).and_return(Doorkeeper::OAuth::Scopes.from_string("name"))
      render
      expect(rendered).to include(identity.first_name)
      expect(rendered).to include(identity.last_name)
    end

    it "shows verification status for verification_status scope" do
      allow(pre_auth).to receive(:scopes).and_return(Doorkeeper::OAuth::Scopes.from_string("verification_status"))
      render
      expect(rendered).to include(identity.verification_status)
      expect(rendered).to include("YSWS eligible")
    end

    it "shows address for address scope" do
      allow(pre_auth).to receive(:scopes).and_return(Doorkeeper::OAuth::Scopes.from_string("address"))
      render
      expect(rendered).to include("Burlington")
    end

    it "shows all basic_info fields for basic_info scope" do
      allow(pre_auth).to receive(:scopes).and_return(Doorkeeper::OAuth::Scopes.from_string("basic_info"))
      render
      expect(rendered).to include(identity.primary_email)
      expect(rendered).to include(identity.first_name)
      expect(rendered).to include(identity.slack_id)
    end

    it "deduplicates when email and basic_info are both requested" do
      allow(pre_auth).to receive(:scopes).and_return(Doorkeeper::OAuth::Scopes.from_string("email basic_info"))
      render
      expect(rendered.scan(identity.primary_email).count).to eq(1)
    end

    it "shows nothing for openid-only scope" do
      allow(pre_auth).to receive(:scopes).and_return(Doorkeeper::OAuth::Scopes.from_string("openid"))
      render
      expect(rendered).not_to include(identity.primary_email)
      expect(rendered).not_to include(identity.first_name)
    end

    it "falls back to i18n for unknown scopes" do
      allow(pre_auth).to receive(:scopes).and_return(Doorkeeper::OAuth::Scopes.from_string("some_future_scope"))
      allow(pre_auth).to receive(:scope).and_return("some_future_scope")
      render
      expect(rendered).to include("Some future scope")
    end
  end

  describe "trust level banners" do
    it "shows warning banner for community_untrusted apps" do
      allow(program).to receive(:trust_level).and_return("community_untrusted")
      render
      expect(rendered).to include("Community Application")
    end

    it "shows info banner for community_trusted apps" do
      allow(program).to receive(:trust_level).and_return("community_trusted")
      render
      expect(rendered).to include("Community Application")
      expect(rendered).to include("reviewed it")
    end

    it "shows no banner for hq_official apps" do
      allow(program).to receive(:trust_level).and_return("hq_official")
      render
      expect(rendered).not_to include("Community Application")
    end
  end

  describe "authorize button" do
    it "has countdown for non-official apps" do
      allow(program).to receive(:hq_official?).and_return(false)
      render
      expect(rendered).to include("countdown: 3")
    end

    it "has no countdown for official apps" do
      allow(program).to receive(:hq_official?).and_return(true)
      render
      expect(rendered).to include("countdown: 0")
    end
  end
end
