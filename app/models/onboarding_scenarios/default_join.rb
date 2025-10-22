module OnboardingScenarios
    class DefaultJoin < Base
        def title
            "Sign up"
        end

        def form_fields
            [ :first_name, :last_name, :primary_email, :birthday, :country ]
        end


        def slack_user_type = :multi_channel_guest

        def slack_channels = Rails.configuration.slack_channels.slice(:announcements).keys

        def promotion_channels = Rails.configuration.slack_channels.slice(:welcome, :ship, :neighbourhood, :library, :lounge).keys
    end
end
