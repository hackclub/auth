module OnboardingScenarios
    class DefaultJoin < Base
        def self.slug = "default"

        def title = "Join us!"

        def form_fields = %i[ first_name last_name primary_email birthday country ]

        def next_action = :slack

        def slack_user_type = :multi_channel_guest
        def slack_channels = if Rails.env.production?
                               %w[]
                             else
                               %w[C09K9P6QWNN C09K69258F7]
                             end
        # def slack_channels = ["C01234567", "C89ABCDEF"]  # Channel IDs
        def promotion_channels = if Rails.env.production?
                                   %w[]
                                 else
                                   %w[]
                                 end
        def slack_onboarding_flow = :internal_tutorial
    end
end