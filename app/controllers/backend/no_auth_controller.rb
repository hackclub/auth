module Backend
  class NoAuthController < ApplicationController
    skip_before_action :authenticate_user!
  end
end
