# Decides which account a relying party request should use, given what's signed
# into this browser plus whatever the request asked for.
#
# Deliberately free of HTTP so the whole decision table is unit-testable. Shared
# by the OIDC authorize endpoint and the SAML SSO endpoint — SAML has no
# `prompt`, so it simply passes none.
class AccountSelectionResolver
  # :proceed        — use decision.identity_session, no UI
  # :chooser        — ask the user; preselect_identity is a suggestion, not a decision
  # :login_required — nothing usable is signed in here
  # :error          — resolve was impossible without UI (prompt=none)
  Decision = Data.define(:action, :identity_session, :preselect_identity, :login_hint, :error) do
    def proceed? = action == :proceed
    def chooser? = action == :chooser
    def login_required? = action == :login_required
    def error? = action == :error
  end

  def initialize(browser_session:, client_kind:, client_ref:, prompt: [], login_hint: nil,
                 id_token_hint_subject: nil, force_chooser: false)
    @browser_session = browser_session
    @client_kind = client_kind
    @client_ref = client_ref
    @prompt = Array(prompt).map(&:to_s)
    @login_hint = login_hint.presence
    @id_token_hint_subject = id_token_hint_subject.presence
    @force_chooser = force_chooser
  end

  def call
    return decide(:login_required) if candidates.empty?

    # id_token_hint is an instruction, not a preference: if the named subject
    # isn't here we must not substitute another account.
    if @id_token_hint_subject.present?
      return decide(:proceed, identity_session: hinted_session) if hinted_session
      return account_selection_required if silent?

      return decide(:chooser)
    end

    return chooser_decision if @force_chooser || @prompt.include?("select_account")

    # A login_hint naming an account that isn't signed in here is still a
    # statement about who the RP expects. Consenting as whoever happens to be
    # signed in would hand over the wrong account without ever saying so, even
    # when that's the only account — so ask (or, when we can't ask, say why).
    if @login_hint.present?
      return decide(:proceed, identity_session: hinted_session) if hinted_session
      return account_selection_required if silent?

      return decide(:chooser)
    end

    if silent?
      return decide(:proceed, identity_session: remembered_session) if remembered_session
      return decide(:proceed, identity_session: candidates.first) if candidates.one?

      return account_selection_required
    end

    return decide(:proceed, identity_session: candidates.first) if candidates.one?
    return decide(:proceed, identity_session: remembered_session) if remembered_session

    chooser_decision
  end

  private

  def silent? = @prompt.include?("none")

  def candidates
    @candidates ||= @browser_session ? @browser_session.live_identity_sessions.to_a : []
  end

  # A login_hint that doesn't match anything here is a hint for the login form,
  # not grounds for picking someone.
  def hinted_session
    return @hinted_session if defined?(@hinted_session)

    @hinted_session =
      if @id_token_hint_subject.present?
        candidates.find { |session| session.identity.public_id == @id_token_hint_subject }
      elsif @login_hint.present?
        normalized = @login_hint.to_s.strip.downcase
        candidates.find { |session| session.identity.primary_email.to_s.downcase == normalized }
      end
  end

  def remembered_session
    return @remembered_session if defined?(@remembered_session)

    @remembered_session =
      @browser_session&.remembered_identity_session(kind: @client_kind, ref: @client_ref)
  end

  def chooser_decision
    decide(:chooser, preselect_identity: (hinted_session || remembered_session)&.identity)
  end

  def account_selection_required = decide(:error, error: :account_selection_required)

  def decide(action, identity_session: nil, preselect_identity: nil, error: nil)
    Decision.new(
      action: action,
      identity_session: identity_session,
      preselect_identity: preselect_identity,
      login_hint: @login_hint,
      error: error
    )
  end
end
