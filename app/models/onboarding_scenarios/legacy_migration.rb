module OnboardingScenarios
  class LegacyMigration < Base
    def title
      "Confirm your details"
    end

    def form_fields
      [ :first_name, :last_name, :primary_email, :birthday, :country ]
    end

    def accepts_adults = true

    def next_action = :slack
  end
end
