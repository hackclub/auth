module OnboardingScenarios
    class LegacyMigration < Base
        # Pull email from a signed param; users only enter name and birthday
        def title
            "Confirm your details"
        end

        def form_fields
            [ :first_name, :last_name, :birthday, :country ]
        end

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
    end
end
