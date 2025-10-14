module OnboardingScenarios
    class Base
        # Public API for scenarios:
        # - form_fields: symbols of fields to render on the signup form
        # - extract_params_proc: Proc executed in controller context to extract attributes
        #   to prefill onboarding (NOT saved here). Should return a Hash or nil on failure.
        # - title: optional heading for the form page

        def title
            "Create your account"
        end

        def form_fields
            []
        end

        def extract_params_proc
            permitted = form_fields
            proc {
                params.require(:identity).permit(*permitted)
                      .to_h
                      .symbolize_keys
            }
        end
    end
end
