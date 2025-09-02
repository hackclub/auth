module API::V1::ApplicationHelper
  def scope(scope, &)
    return unless current_scopes.include?(scope)
    yield
  end
end
