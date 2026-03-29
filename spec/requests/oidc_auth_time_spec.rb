require "rails_helper"

RSpec.describe "OIDC auth_time", type: :request do
  let(:identity) { create(:identity) }
  let(:program) { create(:program, scopes: "openid email") }
  let(:session) { create(:identity_session, identity: identity) }

  # Stub current_session; current_identity and identity_signed_in? derive from it
  def sign_in_as(identity_session)
    allow_any_instance_of(SessionsHelper).to receive(:current_session).and_return(identity_session)
  end

  before do
    sign_in_as(session)

    # ensure a signing key exists for ID token generation (may not be set in CI)
    unless ENV["OIDC_SIGNING_KEY"].present?
      key = OpenSSL::PKey::RSA.generate(2048).to_pem
      Doorkeeper::OpenidConnect.configuration.instance_variable_set(:@signing_key, key)
    end
  end

  after { Current.reset_all }

  def expected_auth_time(s)
    [s.created_at, s.last_step_up_at].compact.max.to_i
  end

  def decode_id_token(jwt)
    JWT.decode(jwt, nil, false).first
  end

  # POST to /oauth/authorize to create the grant, returns [grant, code_string]
  def authorize!(extra_params = {})
    post "/oauth/authorize", params: {
      client_id: program.uid,
      redirect_uri: program.redirect_uri,
      response_type: "code",
      scope: "openid email",
      nonce: "test-nonce"
    }.merge(extra_params)

    # Extract the code from the redirect location
    location = response.headers["Location"]
    code = CGI.parse(URI.parse(location).query)["code"].first
    grant = Doorkeeper::AccessGrant.order(:created_at).last

    [grant, code]
  end

  def exchange_code!(code)
    post "/oauth/token", params: {
      grant_type: "authorization_code",
      code: code,
      redirect_uri: program.redirect_uri,
      client_id: program.uid,
      client_secret: program.secret
    }

    JSON.parse(response.body)
  end

  describe "authorization code flow" do
    it "stamps source_session_id on the grant" do
      grant, _code = authorize!
      expect(grant).to be_present
      expect(grant.source_session_id).to eq(session.id)
    end

    it "returns correct auth_time after code exchange" do
      _grant, code = authorize!
      body = exchange_code!(code)

      expect(response).to have_http_status(:ok)
      expect(body["id_token"]).to be_present

      claims = decode_id_token(body["id_token"])
      expect(claims["auth_time"]).to eq(expected_auth_time(session))
    end

    it "uses the authorizing session, not the newest session" do
      newer_session = identity.sessions.create!(
        session_token: SecureRandom.hex(32),
        expires_at: 1.week.from_now,
        created_at: 1.hour.from_now
      )

      _grant, code = authorize!
      body = exchange_code!(code)

      claims = decode_id_token(body["id_token"])
      expect(claims["auth_time"]).to eq(expected_auth_time(session))
      expect(claims["auth_time"]).not_to eq(expected_auth_time(newer_session))
    end

    it "uses the original auth_time even if the source session has since expired" do
      _grant, code = authorize!
      session.update!(expires_at: 1.hour.ago)

      body = exchange_code!(code)

      claims = decode_id_token(body["id_token"])
      expect(claims["auth_time"]).to eq(expected_auth_time(session))
    end

    it "reflects last_step_up_at when more recent than created_at" do
      session.update!(last_step_up_at: 1.minute.from_now)

      _grant, code = authorize!
      body = exchange_code!(code)

      claims = decode_id_token(body["id_token"])
      expect(claims["auth_time"]).to eq(session.last_step_up_at.to_i)
    end
  end

  describe "IdToken without session context" do
    it "returns nil auth_time when neither source is available" do
      Current.identity_session = nil

      token = create(:oauth_token, resource_owner: identity, application: program, scopes: "openid email")
      id_token = Doorkeeper::OpenidConnect::IdToken.new(token, "nonce")

      expect(id_token.as_json[:auth_time]).to be_nil
    end
  end

  describe "config blocks" do
    describe "auth_time_from_resource_owner" do
      let(:config_block) { Doorkeeper::OpenidConnect.configuration.auth_time_from_resource_owner }

      it "returns auth_time from Current.identity_session" do
        Current.identity_session = session

        # The block uses `return`, so we need instance_exec (same as doorkeeper does)
        controller = Object.new
        result = controller.instance_exec(identity, &config_block)

        expect(result).to eq([session.created_at, session.last_step_up_at].compact.max)
      end

      it "returns nil when Current.identity_session is not set" do
        Current.identity_session = nil

        controller = Object.new
        result = controller.instance_exec(identity, &config_block)

        expect(result).to be_nil
      end
    end
  end
end
