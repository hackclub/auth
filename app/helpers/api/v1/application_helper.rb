module API::V1::ApplicationHelper
  def scope(scope, identity: nil, &)
    return unless current_scopes.include?(scope)
    return unless identity.nil? || identity_authorized_for_scope?(identity, scope)
    yield
  end
end
