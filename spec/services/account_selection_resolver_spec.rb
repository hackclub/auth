require "rails_helper"

RSpec.describe AccountSelectionResolver, type: :model do
  let(:browser_session) { create(:browser_session) }
  let(:work) { create(:identity, primary_email: "nora@hackclub.com") }
  let(:personal) { create(:identity, primary_email: "nora@example.com") }

  def sign_into(identity)
    session = create(:identity_session, identity: identity, browser_session: browser_session)
    browser_session.activate!(session)
    session
  end

  def resolve(**overrides)
    described_class.new(
      browser_session: browser_session,
      client_kind: "oidc",
      client_ref: "client-abc",
      **overrides
    ).call
  end

  context "with nothing signed in" do
    it "requires login" do
      expect(resolve).to be_login_required
    end
  end

  context "with one account" do
    let!(:only) { sign_into(work) }

    it "proceeds with no prompt" do
      decision = resolve

      expect(decision).to be_proceed
      expect(decision.identity_session).to eq(only)
    end

    it "still shows the chooser for prompt=select_account" do
      expect(resolve(prompt: [ "select_account" ])).to be_chooser
    end

    it "proceeds silently for prompt=none" do
      expect(resolve(prompt: [ "none" ])).to be_proceed
    end
  end

  context "with two accounts" do
    let!(:work_session) { sign_into(work) }
    let!(:personal_session) { sign_into(personal) }

    it "asks when nothing indicates which" do
      expect(resolve).to be_chooser
    end

    it "asks for prompt=select_account even with a sticky selection" do
      browser_session.remember_selection!(kind: "oidc", ref: "client-abc", identity: work)

      decision = resolve(prompt: [ "select_account" ])

      expect(decision).to be_chooser
      expect(decision.preselect_identity).to eq(work)
    end

    it "uses the sticky selection when there is no prompt" do
      browser_session.remember_selection!(kind: "oidc", ref: "client-abc", identity: personal)

      decision = resolve

      expect(decision).to be_proceed
      expect(decision.identity_session).to eq(personal_session)
    end

    it "ignores a sticky selection whose session is gone" do
      # A third account keeps the choice ambiguous once the remembered one goes,
      # so this tests the sticky lookup rather than the single-account shortcut.
      sign_into(create(:identity, primary_email: "third@example.com"))
      browser_session.remember_selection!(kind: "oidc", ref: "client-abc", identity: personal)
      personal_session.revoke!(reason: "user_signout")

      expect(resolve).to be_chooser
    end

    describe "login_hint" do
      it "preselects a matching account" do
        decision = resolve(login_hint: "NORA@HACKCLUB.COM ")

        expect(decision).to be_proceed
        expect(decision.identity_session).to eq(work_session)
      end

      it "falls back to the chooser when it matches nothing" do
        decision = resolve(login_hint: "someone@else.com")

        expect(decision).to be_chooser
        expect(decision.login_hint).to eq("someone@else.com")
      end
    end

    describe "id_token_hint" do
      it "constrains selection to the named subject" do
        decision = resolve(id_token_hint_subject: personal.public_id)

        expect(decision).to be_proceed
        expect(decision.identity_session).to eq(personal_session)
      end

      it "does not substitute another account when the subject isn't here" do
        decision = resolve(id_token_hint_subject: "ident_nobody")

        expect(decision).to be_chooser
        expect(decision.identity_session).to be_nil
      end

      it "outranks a sticky selection" do
        browser_session.remember_selection!(kind: "oidc", ref: "client-abc", identity: work)

        decision = resolve(id_token_hint_subject: personal.public_id)

        expect(decision.identity_session).to eq(personal_session)
      end
    end

    describe "prompt=none" do
      it "errors rather than guessing" do
        decision = resolve(prompt: [ "none" ])

        expect(decision).to be_error
        expect(decision.error).to eq(:account_selection_required)
      end

      it "resolves via sticky selection" do
        browser_session.remember_selection!(kind: "oidc", ref: "client-abc", identity: work)

        expect(resolve(prompt: [ "none" ]).identity_session).to eq(work_session)
      end

      it "resolves via login_hint" do
        expect(resolve(prompt: [ "none" ], login_hint: personal.primary_email).identity_session)
          .to eq(personal_session)
      end

      it "errors when an id_token_hint names an account that isn't here" do
        decision = resolve(prompt: [ "none" ], id_token_hint_subject: "ident_nobody")

        expect(decision).to be_error
        expect(decision.error).to eq(:account_selection_required)
      end
    end

    it "asks when the caller forces it" do
      browser_session.remember_selection!(kind: "oidc", ref: "client-abc", identity: work)

      expect(resolve(force_chooser: true)).to be_chooser
    end
  end

  # SAML has no prompt parameter, so policy carries the whole load: ask on first
  # use of an entity ID, remember the answer, and honour a forced re-ask.
  describe "SAML service providers" do
    let(:entity_id) { "https://sp.example.com/metadata" }

    def resolve_saml(**overrides)
      described_class.new(
        browser_session: browser_session,
        client_kind: "saml",
        client_ref: entity_id,
        **overrides
      ).call
    end

    before do
      sign_into(work)
      sign_into(personal)
    end

    it "asks on first use" do
      expect(resolve_saml).to be_chooser
    end

    it "is sticky per entity ID afterwards" do
      browser_session.remember_selection!(kind: "saml", ref: entity_id, identity: work)

      decision = resolve_saml
      expect(decision).to be_proceed
      expect(decision.identity_session.identity).to eq(work)
    end

    it "asks again when forced" do
      browser_session.remember_selection!(kind: "saml", ref: entity_id, identity: work)

      expect(resolve_saml(force_chooser: true)).to be_chooser
    end

    it "does not share a selection with the OIDC client of the same name" do
      browser_session.remember_selection!(kind: "oidc", ref: entity_id, identity: work)

      expect(resolve_saml).to be_chooser
    end
  end
end
