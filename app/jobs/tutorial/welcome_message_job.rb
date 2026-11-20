class Tutorial::WelcomeMessageJob < ApplicationJob
  queue_as :default

  BOT_NAME = "the Viceroy of Virtuous Conduct"
  BOT_ICON_URL = "https://cdn.hackclub.com/019e416e-ac78-7302-b9ea-293897ac4c48/rulespheus.png"

  def perform(identity)
    RalseiEngine.send_message(identity, "tutorial/welcome_to_hackclub", bot_name: BOT_NAME, bot_icon_url: BOT_ICON_URL)
  end
end
