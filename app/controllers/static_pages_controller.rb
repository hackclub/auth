class StaticPagesController < ApplicationController
  skip_before_action :authenticate_identity!, only: [ :faq, :external_api_docs, :welcome ]

  def home
  end

  def welcome
  end

  def faq
  end

  def external_api_docs
    render :external_api_docs, layout: "backend"
  end
end
