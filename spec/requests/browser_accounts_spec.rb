require "rails_helper"

RSpec.describe "Browser accounts", type: :request do
  let(:work) { create(:identity, primary_email: "nora@hackclub.com") }
  let(:personal) { create(:identity, primary_email: "nora@example.com") }

  before { Flipper.enable(BrowserAccountsController::FEATURE_FLAG) }
  after { Flipper.disable(BrowserAccountsController::FEATURE_FLAG) }

  describe "signing a second account into the same browser" do
    it "keeps both accounts in one browser session" do
      first = sign_in_as(work)
      add_account(personal)

      browser_session = first.reload.browser_session
      expect(browser_session).to be_present
      expect(browser_session.live_identity_sessions.map(&:identity)).to contain_exactly(work, personal)
      expect(browser_session.active_identity).to eq(personal)
    end

    it "rotates the browser session token when an account is added" do
      sign_in_as(work)
      browser_session = BrowserSession.order(:created_at).last
      token_before = browser_session.token

      add_account(personal)

      expect(browser_session.reload.token).not_to eq(token_before)
    end

    it "does not create a duplicate session when re-authenticating the same account" do
      original = sign_in_as(work)
      original.update!(expires_at: 1.minute.from_now)

      add_account(work)

      renewed = work.sessions.reload.select(&:live?).sole
      expect(renewed.id).not_to eq(original.id)
      expect(renewed.expires_at).to be_within(5.seconds).of(SessionsHelper::SESSION_DURATION.from_now)
      expect(original.reload.revoked_reason).to eq("reauthenticated")
      expect(LoginAttempt.where(identity: work).order(:created_at).last.session).to eq(renewed)
    end

    it "records the addition without naming the other account" do
      sign_in_as(work)
      add_account(personal)

      activity = PublicActivity::Activity.find_by(key: "identity_session.account_added")
      expect(activity).to be_present
      expect(activity.recipient_id).to eq(personal.id)
      expect(activity.parameters.to_s).not_to include(work.primary_email)
    end
  end

  describe "GET /accounts" do
    before do
      sign_in_as(work)
      add_account(personal)
      get browser_accounts_path
    end

    it "lists every account with its full email" do
      expect(response.body).to include(work.primary_email)
      expect(response.body).to include(personal.primary_email)
    end

    it "distinguishes work from personal with a text label, not colour alone" do
      expect(response.body).to include("Hack Club")
      expect(response.body).to include("Personal")
    end
  end

  describe "switching" do
    it "changes the active account" do
      work_session = sign_in_as(work)
      add_account(personal)

      post switch_browser_account_path, params: { id: work.public_id }

      expect(BrowserSession.order(:created_at).last.active_identity).to eq(work)
      expect(work_session.reload).to be_live
    end

    it "refuses an account that isn't in this browser" do
      sign_in_as(work)
      stranger = create(:identity, primary_email: "stranger@example.com")

      post switch_browser_account_path, params: { id: stranger.public_id }

      expect(BrowserSession.order(:created_at).last.active_identity).to eq(work)
    end

    it "is not reachable by GET" do
      sign_in_as(work)

      get "/accounts/switch"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "removing an account" do
    it "leaves the active account alone" do
      sign_in_as(personal)
      add_account(work)
      post switch_browser_account_path, params: { id: personal.public_id }

      delete browser_account_path(id: work.public_id)

      expect(work.sessions.reload.select(&:live?)).to be_empty
      expect(personal.sessions.reload.select(&:live?).size).to eq(1)
      expect(BrowserSession.order(:created_at).last.active_identity).to eq(personal)
    end

    it "ends the browser session when the last account is removed" do
      sign_in_as(work)

      delete browser_account_path(id: work.public_id)

      expect(BrowserSession.count).to eq(0)
      expect(response).to redirect_to(welcome_path)
    end

    it "keeps a parked authorization attached after removing an account" do
      sign_in_as(personal)
      add_account(work)
      browser_session = BrowserSession.order(:created_at).last
      pending = create(:pending_authorization, browser_session: browser_session)

      get browser_accounts_path(pending: pending.token)
      expect(response.body).to include(%(name="pending" value="#{pending.token}"))

      delete browser_account_path(id: work.public_id), params: { pending: pending.token }

      expect(response).to redirect_to(browser_accounts_path(pending: pending.token))
      expect(pending.reload).not_to be_consumed
    end
  end

  describe "the account cap" do
    it "refuses to add more than MAX_ACCOUNTS and evicts nothing" do
      sign_in_as(work)
      (BrowserSession::MAX_ACCOUNTS - 1).times do |i|
        add_account(create(:identity, primary_email: "extra#{i}@example.com"))
      end

      browser_session = BrowserSession.order(:created_at).last
      expect(browser_session.account_count).to eq(BrowserSession::MAX_ACCOUNTS)

      post add_browser_account_path

      expect(response).to redirect_to(browser_accounts_path)
      expect(flash[:error]).to include("maximum number of accounts")
      expect(browser_session.reload.account_count).to eq(BrowserSession::MAX_ACCOUNTS)
    end

    # Two logins started side by side can both pass the cap check and only one can
    # win the last slot. The loser used to raise AccountLimitError out of sign_in,
    # mid-transaction, as a 500. Both stubs stand for state that was true a moment
    # earlier in that race: the flag was set while there was still room, and the
    # pre-check passed before the other request committed.
    it "ends a login that loses the race for the last slot with a message, not a 500" do
      sign_in_as(work)
      (BrowserSession::MAX_ACCOUNTS - 1).times do |i|
        add_account(create(:identity, primary_email: "extra#{i}@example.com"))
      end

      browser_session = BrowserSession.order(:created_at).last
      expect(browser_session.account_count).to eq(BrowserSession::MAX_ACCOUNTS)

      allow_any_instance_of(LoginsController).to receive(:adding_account?).and_return(true)
      allow_any_instance_of(LoginsController).to receive(:browser_account_limit_reached?).and_return(false)

      newcomer = create(:identity, primary_email: "one-too-many@example.com")
      expect { sign_in_as(newcomer) }.not_to change { IdentitySession.count }

      expect(response).to redirect_to(browser_accounts_path)
      expect(flash[:error]).to include("maximum number of accounts")
      expect(newcomer.sessions.reload).to be_empty
      expect(browser_session.reload.account_count).to eq(BrowserSession::MAX_ACCOUNTS)
    end
  end

  describe "with the flag off" do
    it "degrades to the active account instead of erroring" do
      sign_in_as(work)
      add_account(personal)
      Flipper.disable(BrowserAccountsController::FEATURE_FLAG)

      get browser_accounts_path
      expect(response).to redirect_to(root_path)

      get root_path
      expect(response).to have_http_status(:ok).or redirect_to(anything)
    end
  end

  describe "when the active account expires with siblings still signed in" do
    it "sends the user to the chooser rather than a login screen" do
      sign_in_as(work)
      personal_session = add_account(personal)
      personal_session.update!(expires_at: 1.minute.ago)

      get root_path

      expect(response).to redirect_to(browser_accounts_path)

      follow_redirect!
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(work.primary_email)
    end

    it "still goes to welcome when the chooser is switched off" do
      sign_in_as(work)
      personal_session = add_account(personal)
      personal_session.update!(expires_at: 1.minute.ago)
      Flipper.disable(BrowserAccountsController::FEATURE_FLAG)

      get root_path

      expect(response.headers["Location"]).to include(welcome_path)
    end
  end

  describe "sign-out" do
    it "signs out only the active account by default" do
      sign_in_as(work)
      add_account(personal)

      delete logout_path

      expect(personal.sessions.reload.select(&:live?)).to be_empty
      expect(work.sessions.reload.select(&:live?).size).to eq(1)
      expect(response).to redirect_to(browser_accounts_path)
    end

    # The browser session cookie survives; everything the departing account left
    # in the Rails session does not.
    it "discards the signed-out account's session data" do
      sign_in_as(work)
      add_account(personal)

      delete logout_path

      leftovers = session.to_hash.except("session_id", "_csrf_token", "flash")
      expect(leftovers).to be_empty
      expect(BrowserSession.count).to eq(1)
    end

    it "does not promote a sibling into the active slot" do
      sign_in_as(work)
      add_account(personal)

      delete logout_path

      expect(BrowserSession.order(:created_at).last.active_session).to be_nil
    end

    it "signs out of everything on request" do
      sign_in_as(work)
      add_account(personal)

      delete logout_all_path

      expect(work.sessions.reload.select(&:live?)).to be_empty
      expect(personal.sessions.reload.select(&:live?)).to be_empty
      expect(BrowserSession.count).to eq(0)
      expect(response).to redirect_to(welcome_path)
    end
  end

  describe "legacy sessions" do
    it "adopts a pre-multi-account cookie without signing the user out" do
      sign_in_as(work)
      browser_session = BrowserSession.order(:created_at).last
      ident_session = browser_session.active_identity_session

      # Rewind to the old world: cookie value points straight at the account
      # session and no browser session exists.
      legacy_token = browser_session.token
      ident_session.update!(browser_session_id: nil, session_token: legacy_token)
      browser_session.destroy!

      get root_path

      adopted = IdentitySession.find(ident_session.id).browser_session
      expect(adopted).to be_present
      expect(adopted.active_identity_session_id).to eq(ident_session.id)
      expect(response).not_to redirect_to(welcome_path)
    end
  end
end
