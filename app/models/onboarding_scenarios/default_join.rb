module OnboardingScenarios
    class DefaultJoin < Base
        def title
            "Sign up"
        end

        def form_fields
            [ :first_name, :last_name, :primary_email, :birthday, :country ]
        end
    end
end
