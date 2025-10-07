module OnboardingScenarios
    class DefaultJoin < Base
        def title = "Join us!"

        def form_fields = %i[ first_name last_name primary_email birthday country ]

        def next_action = :slack

    end
end