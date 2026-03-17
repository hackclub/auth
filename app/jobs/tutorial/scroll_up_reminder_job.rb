class Tutorial::ScrollUpReminderJob < ApplicationJob
  queue_as :default

  def perform(identity)
    return if identity.promote_click_count > 0

    RalseiEngine.send_message(identity, "tutorial/scroll_up_reminder")
  end
end
