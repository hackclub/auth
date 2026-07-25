# frozen_string_literal: true

# Account selection for the SAML IdP.
#
# SAML has no equivalent of prompt=select_account, so policy stands in for
# protocol: the first SSO to a service provider from a browser holding several
# accounts asks, and the answer is remembered per entity ID. `?select_account=1`
# forces the question again.
#
# IdP-initiated flows always ask, because there is no SP request to correlate
# against and nothing trustworthy to disambiguate with.
module SAMLAccountSelection
  extend ActiveSupport::Concern

  CLIENT_KIND = "saml"

  included do
    helper_method :saml_identity
  end

  # The account this SSO is for. Falls back to the active account when selection
  # doesn't apply (single account, or the chooser is off).
  def saml_identity
    @saml_selected_identity || current_identity
  end

  private

  # Returns false when it has redirected or rendered, matching the `return unless`
  # style the rest of SAMLController uses.
  def resolve_saml_account!(entity_id:, force_chooser: false)
    return true unless account_chooser_available?

    decision = AccountSelectionResolver.new(
      browser_session: current_browser_session,
      client_kind: CLIENT_KIND,
      client_ref: entity_id,
      force_chooser: force_chooser || params[:select_account].present?
    ).call

    case decision.action
    when :proceed
      @saml_selected_identity = decision.identity_session.identity
      true
    when :chooser
      park_saml_request_and_choose(entity_id: entity_id, decision: decision)
      false
    else
      # :login_required is handled by SAMLController's own current_identity check.
      true
    end
  end

  # The chooser records the choice and activates the account, so the parked
  # request can simply be replayed unchanged afterwards.
  def park_saml_request_and_choose(entity_id:, decision:)
    pending = PendingAuthorization.park!(
      browser_session: current_browser_session,
      kind: CLIENT_KIND,
      payload: { "url" => request.fullpath, "entity_id" => entity_id }
    )

    redirect_to browser_accounts_path(
      pending: pending.token,
      preselect: decision.preselect_identity&.public_id
    )
  end

  # IdP-initiated can't be parked and replayed — there's no GET to come back to —
  # so the chooser is rendered inline and posts straight back to this endpoint.
  def render_saml_inline_chooser(entity_id:)
    decision = AccountSelectionResolver.new(
      browser_session: current_browser_session,
      client_kind: CLIENT_KIND,
      client_ref: entity_id,
      force_chooser: true
    ).call

    @accounts = eligible_saml_accounts
    @preselect_public_id = decision.preselect_identity&.public_id
    @submit_params = request.params.slice("slug").merge("select_account" => nil).compact

    render "saml/choose_account"
  end

  def resolve_saml_account_from_params!(entity_id:)
    return true if params[:selected_account].blank?

    session_for_selection = eligible_saml_accounts.find do |ident_session|
      ident_session.identity.public_id == params[:selected_account]
    end

    if session_for_selection.nil?
      @error = "That account isn't signed in on this browser."
      render :error, status: :bad_request
      return false
    end

    @saml_selected_identity = session_for_selection.identity
    current_browser_session&.remember_selection!(
      kind: CLIENT_KIND, ref: entity_id, identity: session_for_selection.identity
    )
    true
  end

  # Offering an account the SP will reject is worse than not offering it. Filtered
  # against the same allowed_emails list the SSO endpoints enforce.
  def eligible_saml_accounts
    sessions = current_browser_session&.live_identity_sessions&.includes(:identity, :login_attempt) || []
    allowed = @sp_config&.dig(:allowed_emails)
    return sessions.to_a if allowed.blank?

    sessions.select { |ident_session| allowed.include?(ident_session.identity.primary_email) }
  end

  def saml_account_selection_needed?
    return false unless account_chooser_available?

    eligible_saml_accounts.size > 1
  end
end
