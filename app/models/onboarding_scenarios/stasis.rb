module OnboardingScenarios
  class Stasis < Base
    def self.slug = "stasis"

    def title
      "Ready to hack hardware with us?"
    end

    def form_fields
      [ :first_name, :last_name, :primary_email, :birthday, :country ]
    end

    def next_action = :home
  end
end
