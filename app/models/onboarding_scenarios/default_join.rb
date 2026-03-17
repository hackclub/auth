module OnboardingScenarios
    class DefaultJoin < Base
        def title
            "Sign up"
        end

        def form_fields
            [ :first_name, :last_name, :primary_email, :birthday, :country ]
        end


        def slack_user_type = :multi_channel_guest

        def next_action = :slack

        def slack_onboarding_flow = :internal_tutorial

        def slack_channels = Rails.configuration.slack_channels.slice(:welcome_to_hack_club).values

        def promotion_channels = Rails.configuration.slack_channels.slice(:announcements, :happenings, :community, :hardware, :code, :ship, :neighbourhood, :library, :lounge).values

        def send_ephemeral_in_channel? = true

        def ephemeral_channel = Rails.configuration.slack_channels[:welcome_to_hack_club]
    end
end
