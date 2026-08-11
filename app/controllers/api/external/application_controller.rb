module API
  module External
    class ApplicationController < ActionController::API
      # Read-only access to current_identity via the encrypted session cookie.
      include ActionController::Cookies
      include SessionsHelper
    end
  end
end
