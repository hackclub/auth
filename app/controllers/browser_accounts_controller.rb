class BrowserAccountsController < ApplicationController
  layout "logged_out"

  FEATURE_FLAG = :multi_account_sessions_2026_07_24

  # Reachable with no active account: signing one account out leaves the browser
  # session alive with the others, and we never auto-promote a sibling.
  skip_before_action :authenticate_identity!

  before_action :require_browser_session
  before_action :require_feature_flag

  def index
    @accounts = accounts
    @pending_token = params[:pending]
    @preselect_public_id = params[:preselect]
    @at_account_limit = current_browser_session.at_account_limit?
  end

  def switch
    target = find_account(params[:id])
    return account_not_found if target.nil?

    switch_account!(target)
    remember_pending_selection(target)

    resume_or(root_path)
  end

  # Leaves mid-flow to authenticate a different account, then comes back. The
  # parked request travels as an opaque handle in return_to, so the login flow
  # itself needs no knowledge of any of this.
  def add
    if current_browser_session.at_account_limit?
      flash[:error] = "You're signed into the maximum number of accounts in this browser. Sign one out first."
      return redirect_to browser_accounts_path(pending: params[:pending])
    end

    # Lets LoginsController#ensure_no_user! through for this flow only.
    session[:adding_account] = true

    return_to = params[:pending].present? ? resume_browser_account_path(pending: params[:pending]) : root_path
    redirect_to login_path(return_to: return_to)
  end

  def destroy
    target = find_account(params[:id])
    return account_not_found if target.nil?

    result = remove_account!(target)
    flash[:info] = "Signed out of #{target.identity.primary_email}."

    if result == :signed_out
      redirect_to welcome_path
    else
      redirect_to browser_accounts_path(pending: params[:pending])
    end
  end

  def resume
    pending = PendingAuthorization.consume!(
      token: params[:pending],
      browser_session: current_browser_session
    )

    if pending.nil?
      flash[:error] = "That sign-in request expired. Start again from the app you were signing into."
      return redirect_to root_path
    end

    session.delete(:adding_account)
    redirect_to rebuilt_request_path(pending), allow_other_host: false
  end

  private

  def accounts
    current_browser_session
      .live_identity_sessions
      .includes(:identity, :login_attempt)
  end

  def find_account(public_id)
    return nil if public_id.blank?

    accounts.find { |session| session.identity.public_id == public_id }
  end

  def account_not_found
    flash[:error] = "That account isn't signed in on this browser."
    redirect_to browser_accounts_path
  end

  def require_browser_session
    return if current_browser_session&.live_identity_sessions&.exists?

    redirect_to welcome_path
  end

  def require_feature_flag
    return if Flipper.enabled?(FEATURE_FLAG, current_identity)

    redirect_to root_path
  end

  # Recording the choice before resuming means the replayed request resolves to
  # this account without needing to carry it in the URL.
  def remember_pending_selection(identity_session)
    pending = PendingAuthorization.active.find_by(token: params[:pending])
    return if pending.nil? || pending.browser_session_id != current_browser_session.id

    kind, ref = client_reference_for(pending)
    return if ref.blank?

    current_browser_session.remember_selection!(kind: kind, ref: ref, identity: identity_session.identity)
  end

  def client_reference_for(pending)
    case pending.kind
    when "oidc"
      [ "oidc", pending.payload.dig("params", "client_id") ]
    when "saml"
      [ "saml", pending.payload["entity_id"] ]
    end
  end

  def resume_or(fallback)
    return redirect_to(resume_browser_account_path(pending: params[:pending])) if params[:pending].present?

    redirect_to fallback
  end

  # Only ever rebuilds a request we parked ourselves, and only to the two
  # endpoints that can park one.
  def rebuilt_request_path(pending)
    case pending.kind
    when "oidc"
      authorize_params = pending.payload["params"] || {}
      "/oauth/authorize?#{authorize_params.to_query}"
    when "saml"
      url = pending.payload["url"].to_s
      url.start_with?("/saml/auth") ? url : root_path
    else
      root_path
    end
  end
end
