class Tutorial::AgreeJob < ApplicationJob
  queue_as :default

  def perform(identity)
    RalseiEngine.handle_tutorial_agree(identity)
  end
end
