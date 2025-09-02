class StaticPagesController < ApplicationController
  skip_before_action :authenticate_identity!, only: [ :faq, :external_api_docs ]

  def index
  end

  def faq
  end

  def external_api_docs
    render :external_api_docs, layout: "backend"
  end
end
