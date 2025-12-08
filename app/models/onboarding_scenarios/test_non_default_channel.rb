module OnboardingScenarios
  class TestNonDefaultChannel < Base
    # forgive me, i gotta test this on prod Slack

    def self.slug = "test_ndc"

    def title = "i wonder if this will do anything?"

    def form_fields
      [ :first_name, :last_name, :primary_email, :birthday, :country ]
    end

    def slack_user_type = :multi_channel_guest

    def next_action = :slack

    def slack_onboarding_flow = :internal_tutorial

    def slack_channels = Rails.configuration.slack_channels.slice(:hq_eng).values

    def promotion_channels = Rails.configuration.slack_channels.slice(:welcome, :ship, :neighbourhood, :library, :lounge).values
  end
end
