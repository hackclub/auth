module Backend
  class NoAuthController < Backend::ApplicationController
    skip_before_action :authenticate_user!
  end
end
