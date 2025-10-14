class StaticPagesController < ApplicationController
  skip_before_action :authenticate_identity!, only: [ :faq, :external_api_docs, :welcome, :oauth_welcome ]

  def home
    @sso_apps = SAMLService::Entities.service_providers.values.select { |sp| sp[:allow_idp_initiated] }
  end

  def welcome
    render layout: "logged_out"
  end

  def oauth_welcome
    # Extract client_id from the oauth_return_to URL
    @oauth_return_to = session[:oauth_return_to]
    if @oauth_return_to.present?
      uri = URI.parse(@oauth_return_to)
      params_hash = URI.decode_www_form(uri.query || "").to_h
      client_id = params_hash["client_id"]
      @program = Program.find_by(uid: client_id) if client_id
    end
    
    @program ||= nil
    render layout: "logged_out"
  end

  def faq
  end

  def external_api_docs
    render :external_api_docs, layout: "backend"
  end

  def security
  end
end
