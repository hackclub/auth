module StepUpAuthenticatable
  extend ActiveSupport::Concern

  included do
    helper_method :step_up_required?
  end

  private

  def require_step_up(action_type, return_to: nil)
    return unless current_identity.has_two_factor_method?
    return if current_session.recently_stepped_up?(for_action: action_type)

    redirect_to new_step_up_path(action_type: action_type, return_to: return_to || request.fullpath)
    false
  end

  def step_up_required?(action_type = nil)
    current_identity.has_two_factor_method? && !current_session.recently_stepped_up?(for_action: action_type)
  end

  def consume_step_up!
    current_session.clear_step_up!
  end
end
