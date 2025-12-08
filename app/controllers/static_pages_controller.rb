class StaticPagesController < ApplicationController
  skip_before_action :authenticate_identity!, only: [ :external_api_docs, :welcome, :oauth_welcome ]

  def home
    @sso_apps = SAMLService::Entities.service_providers.values.select { |sp| sp[:allow_idp_initiated] }
  end

  def welcome
    @return_to = params[:return_to]
    render layout: "logged_out"
  end

  def oauth_welcome
    # Extract client_id and login_hint from the return_to URL
    @return_to = params[:return_to]
    @login_hint = nil
    if @return_to.present?
      uri = URI.parse(@return_to)
      params_hash = URI.decode_www_form(uri.query || "").to_h
      client_id = params_hash["client_id"]
      @program = Program.find_by(uid: client_id) if client_id

      # Extract login_hint (OIDC standard parameter for prefilling email)
      login_hint = params_hash["login_hint"]
      @login_hint = login_hint if login_hint.present? && valid_email_format?(login_hint)
    end

    @program ||= nil
    render layout: "logged_out"
  end

  def external_api_docs
    render :external_api_docs, layout: "backend"
  end

  def security
  end

  private

  def valid_email_format?(email)
    email.to_s.match?(/\A[^@\s]+@[^@\s]+\z/)
  end
end