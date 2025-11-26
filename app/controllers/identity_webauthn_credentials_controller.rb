class IdentityWebauthnCredentialsController < ApplicationController
  def index
    @webauthn_credentials = []
    render layout: request.headers["HX-Request"] ? "htmx" : false
  end

  def new
    render layout: request.headers["HX-Request"] ? "htmx" : false
  end
end
