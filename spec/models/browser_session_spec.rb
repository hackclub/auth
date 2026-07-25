require "rails_helper"

RSpec.describe BrowserSession, type: :model do
  let(:browser_session) { create(:browser_session) }
  let(:identity) { create(:identity) }

  def add_account(session, account_identity = create(:identity))
    ident_session = create(:identity_session, identity: account_identity, browser_session: session)
    session.activate!(ident_session)
    ident_session
  end

  describe "account membership" do
    it "lists live accounts oldest first" do
      first = add_account(browser_session)
      second = add_account(browser_session)

      expect(browser_session.live_identity_sessions.to_a).to eq([ first, second ])
    end

    it "excludes expired and signed-out accounts" do
      live = add_account(browser_session)
      expired = create(:identity_session, :expired, browser_session: browser_session)
      signed_out = add_account(browser_session)
      signed_out.revoke!(reason: "user_signout")

      expect(browser_session.live_identity_sessions).to contain_exactly(live)
      expect(browser_session.live_identity_sessions).not_to include(expired)
    end

    it "caps the number of accounts" do
      described_class::MAX_ACCOUNTS.times { add_account(browser_session) }

      expect(browser_session).to be_at_account_limit
    end

    it "refuses to activate a session belonging to another browser session" do
      other = add_account(create(:browser_session))

      expect { browser_session.activate!(other) }.to raise_error(ArgumentError)
    end
  end

  describe "#active_session" do
    it "returns nil rather than promoting a sibling when the active account expires" do
      active = add_account(browser_session)
      sibling = add_account(browser_session)
      browser_session.activate!(active)

      active.update!(expires_at: 1.minute.ago)

      expect(browser_session.reload.active_session).to be_nil
      expect(browser_session.live_identity_sessions).to include(sibling)
    end

    it "returns nil for a signed-out active account" do
      active = add_account(browser_session)
      active.revoke!(reason: "user_signout")

      expect(browser_session.reload.active_session).to be_nil
    end
  end

  describe "expiry independence" do
    it "does not extend a sibling's expiry when another account is added" do
      first = add_account(browser_session)
      original_expiry = first.expires_at

      travel_to(2.days.from_now) do
        add_account(browser_session)
        expect(first.reload.expires_at).to be_within(1.second).of(original_expiry)
      end
    end

    it "only extends the browser session forwards" do
      browser_session.update!(expires_at: 10.days.from_now)

      browser_session.extend_expiry!(1.day.from_now)
      expect(browser_session.expires_at).to be_within(1.minute).of(10.days.from_now)

      browser_session.extend_expiry!(30.days.from_now)
      expect(browser_session.expires_at).to be_within(1.minute).of(30.days.from_now)
    end
  end

  describe "#rotate_token!" do
    it "changes the token without disturbing the accounts" do
      account = add_account(browser_session)
      before = browser_session.token

      browser_session.rotate_token!

      expect(browser_session.token).not_to eq(before)
      expect(browser_session.reload.live_identity_sessions).to include(account)
      expect(browser_session.active_identity_session_id).to eq(account.id)
    end
  end

  describe "sticky selections" do
    it "remembers and returns the session for a client" do
      account = add_account(browser_session, identity)

      browser_session.remember_selection!(kind: "oidc", ref: "client-abc", identity: identity)

      expect(browser_session.remembered_identity_session(kind: "oidc", ref: "client-abc")).to eq(account)
    end

    it "treats a remembered account with no live session as absent" do
      account = add_account(browser_session, identity)
      browser_session.remember_selection!(kind: "oidc", ref: "client-abc", identity: identity)
      account.revoke!(reason: "user_signout")

      expect(browser_session.remembered_identity_session(kind: "oidc", ref: "client-abc")).to be_nil
    end

    it "keys selections separately per client and kind" do
      add_account(browser_session, identity)
      browser_session.remember_selection!(kind: "oidc", ref: "same-ref", identity: identity)

      expect(browser_session.remembered_identity_session(kind: "saml", ref: "same-ref")).to be_nil
    end

    # Two tabs authorizing the same client race the unique index. The upsert has
    # to move the pointer in place: a second row is impossible, and an exception
    # here would poison whatever transaction we were called from.
    it "moves an existing selection instead of inserting a second row" do
      first = add_account(browser_session, identity)
      other_identity = create(:identity)
      second = add_account(browser_session, other_identity)

      browser_session.remember_selection!(kind: "oidc", ref: "client-abc", identity: identity)
      created_at = browser_session.client_selections.sole.created_at

      browser_session.remember_selection!(kind: "oidc", ref: "client-abc", identity: other_identity)

      selection = browser_session.client_selections.reload.sole
      expect(selection.identity_id).to eq(other_identity.id)
      expect(selection.created_at).to be_within(1.second).of(created_at)
      expect(browser_session.remembered_identity_session(kind: "oidc", ref: "client-abc")).to eq(second)
      expect(first.reload).to be_live
    end

    it "keeps working when called from inside a transaction" do
      add_account(browser_session, identity)

      expect do
        ActiveRecord::Base.transaction do
          browser_session.remember_selection!(kind: "oidc", ref: "client-abc", identity: identity)
          browser_session.remember_selection!(kind: "oidc", ref: "client-abc", identity: identity)
        end
      end.not_to raise_error

      expect(browser_session.client_selections.reload.count).to eq(1)
    end

    it "refuses a client kind it doesn't know" do
      add_account(browser_session, identity)

      expect { browser_session.remember_selection!(kind: "ldap", ref: "x", identity: identity) }
        .to raise_error(ArgumentError)
    end
  end

  describe "#touch_last_seen_at" do
    it "records activity, then holds off until the cooldown passes" do
      expect(browser_session.last_seen).to be_nil

      browser_session.touch_last_seen_at
      first_seen = browser_session.reload.last_seen
      expect(first_seen).to be_present

      browser_session.touch_last_seen_at
      expect(browser_session.reload.last_seen).to be_within(1.second).of(first_seen)

      travel_to(described_class::LAST_SEEN_AT_COOLDOWN.from_now + 1.minute) do
        browser_session.touch_last_seen_at
        expect(browser_session.reload.last_seen).to be > first_seen
      end
    end
  end

  describe "audit trail" do
    it "never versions the token, its ciphertext, or its blind index" do
      browser_session.rotate_token!

      versioned = PaperTrail::Version
        .where(item_type: "BrowserSession", item_id: browser_session.id)
        .flat_map { |version| (version.object_changes || {}).keys }

      expect(versioned).not_to include("token", "token_ciphertext", "token_bidx")
    end
  end

  describe "validations" do
    it "refuses a browser session with no token" do
      expect(described_class.new(expires_at: 1.day.from_now)).not_to be_valid
    end
  end
end
