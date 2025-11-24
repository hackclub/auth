class Tutorial::CocContinueJob < ApplicationJob
  queue_as :default

  def perform(identity)
    RalseiEngine.send_first_message_part2(identity)
  end
end
