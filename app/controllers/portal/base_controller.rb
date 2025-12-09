class Portal::BaseController < ApplicationController
  include PortalFlow

  layout "logged_out"

  helper_method :portal_return_url
end
