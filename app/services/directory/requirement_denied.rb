# frozen_string_literal: true

module Directory
  # raised from the resource-owner authenticator and answered by doorkeeper's own
  # redirect_or_render (see the doorkeeper initializer), so the client gets access_denied +
  # state in whatever shape it asked for: a redirect, or form_post's auto-submitting page.
  # not an OIDC error on purpose: doorkeeper-openid_connect's handler forces a JSON
  # content type, which breaks form_post, and would turn prompt=none into login_required.
  class RequirementDenied < StandardError; end
end
