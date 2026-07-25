# frozen_string_literal: true

# Account selection for the OIDC authorize endpoint.
#
# doorkeeper-openid_connect handles prompt=login and max_age for us (once
# auth_time comes from the right session), but it has no id_token_hint support,
# no way to return account_selection_required, and its select_account hook is
# unconfigured — which currently makes prompt=select_account a hard error.
#
# This runs ahead of the gem's authenticate_resource_owner! chain: if it
# redirects, the gem never sees the request.
module OidcAccountSelection
  extend ActiveSupport::Concern

  CLIENT_KIND = "oidc"

  included do
    prepend_before_action :resolve_oidc_account_selection, only: [ :new, :create ]
  end

  # Consulted by Doorkeeper's resource_owner_authenticator so the grant is issued
  # to the selected account rather than whichever one happens to be active.
  def oidc_selected_identity
    @oidc_selected_identity
  end

  private

  def resolve_oidc_account_selection
    return if params[:client_id].blank?

    hint = IdTokenHintVerifier.call(params[:id_token_hint], audience: params[:client_id])
    return render_oidc_selection_error(:invalid_request) if hint.invalid?

    decision = AccountSelectionResolver.new(
      browser_session: current_browser_session,
      client_kind: CLIENT_KIND,
      client_ref: params[:client_id],
      prompt: params[:prompt].to_s.split(/ +/),
      login_hint: params[:login_hint],
      id_token_hint_subject: hint.subject
    ).call

    case decision.action
    when :login_required
      # Nothing signed in here: fall through to the normal unauthenticated path
      # (resource_owner_authenticator redirects to /oauth/welcome).
      nil
    when :error
      render_oidc_selection_error(decision.error)
    when :chooser
      return select_oidc_account(decision) if account_chooser_available?

      # Chooser disabled: behave exactly as before, using the active account.
      apply_oidc_selection(current_session)
    when :proceed
      # A stale tab must not approve consent for an account other than the one
      # whose data it displayed.
      if request.post? && params[:selected_account].present? &&
          params[:selected_account] != decision.identity_session.identity.public_id
        return select_oidc_account(decision)
      end

      apply_oidc_selection(decision.identity_session)
    end
  end

  def apply_oidc_selection(identity_session)
    return if identity_session.nil?

    @oidc_selected_identity = identity_session.identity
    Current.identity_session = identity_session
  end

  def select_oidc_account(decision)
    pending = PendingAuthorization.park!(
      browser_session: current_browser_session,
      kind: CLIENT_KIND,
      payload: oidc_pending_payload
    )

    redirect_to browser_accounts_path(
      pending: pending.token,
      preselect: decision.preselect_identity&.public_id
    )
  end

  def oidc_pending_payload
    { "params" => request.request_parameters.merge(request.query_parameters).except("selected_account") }
  end

  # OIDC error responses belong on the client's redirect_uri, not on an HTML
  # error page — the RP has to be able to see them.
  def render_oidc_selection_error(name)
    error_response =
      if name == :invalid_request
        Doorkeeper::OAuth::InvalidRequestResponse.new(
          name: name,
          state: params[:state],
          redirect_uri: params[:redirect_uri]
        )
      else
        Doorkeeper::OAuth::ErrorResponse.new(
          name: name,
          state: params[:state],
          redirect_uri: params[:redirect_uri]
        )
      end

    response.headers.merge!(error_response.headers)

    if params[:redirect_uri].present?
      redirect_to error_response.redirect_uri, allow_other_host: true
    else
      render json: { error: name }, status: :bad_request
    end
  end
end
