class StaticPagesController < ApplicationController
  skip_before_action :authenticate_identity!, only: [ :faq, :external_api_docs, :welcome ]

  def home
    @sso_apps = SAMLService::Entities.service_providers.values.select { |sp| sp[:allow_idp_initiated] }
  end

  def welcome
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
