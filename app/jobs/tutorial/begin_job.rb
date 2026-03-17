class Tutorial::BeginJob < ApplicationJob
  queue_as :default

  def perform(identity)
    sleep 3
    RalseiEngine.send_first_message(identity)
  end
end
