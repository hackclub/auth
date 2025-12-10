class Ralsei::HandleActionJob < ApplicationJob
  queue_as :default

  def perform(identity, action_id)
    RalseiEngine.handle_action(identity, action_id)
  end
end
