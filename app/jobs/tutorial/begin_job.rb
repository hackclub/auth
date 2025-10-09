class Tutorial::BeginJob < ApplicationJob
  queue_as :default

  def perform(identity)
    RalseiEngine.send_first_message(identity)
  end
end
