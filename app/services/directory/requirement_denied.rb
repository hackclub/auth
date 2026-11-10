# frozen_string_literal: true

module Directory
  # raised from the resource-owner authenticator so doorkeeper-openid_connect's own error
  # path answers the client (access_denied + state, to the redirect_uri doorkeeper already
  # validated), including for prompt=none, which would otherwise come back login_required.
  class RequirementDenied < Doorkeeper::OpenidConnect::Errors::OpenidConnectError
    def type = :access_denied
  end
end
