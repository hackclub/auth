module OnboardingScenarios
  class LegacyMigration < Base
    def title
      "Confirm your details"
    end

    def form_fields
      [ :first_name, :last_name, :primary_email, :birthday, :country ]
    end

    def accepts_adults = true

    # Existing users being migrated — they don't need the welcome tutorial
    def slack_onboarding_flow = :external_program

    def next_action = :slack
  end
end
