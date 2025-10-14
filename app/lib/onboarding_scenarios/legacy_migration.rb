module OnboardingScenarios
    class LegacyMigration < Base
        def self.slug = "legacy"

        # Pull email from a signed param; users only enter name and birthday
        def title = "Confirm your details"

        def form_fields = %i[ first_name last_name birthday country ]

        def next_action = :home

        def extract_params_proc
            permitted = form_fields
            proc {
                # Expect a signed token param named :email_token (purpose :legacy_email)
                email = nil
                token = params[:email_token]
                if token.present?
                    begin
                        email = Rails.application.message_verifier(:legacy_email).verify(token)
                    rescue StandardError
                        email = nil
                    end
                end

                base_attrs = begin
                    params.require(:identity).permit(*permitted).to_h.symbolize_keys
                rescue StandardError
                    {}
                end

                email.present? ? base_attrs.merge(primary_email: email) : base_attrs
            }
        end

        def next_action
            :home
        end
    end
end
