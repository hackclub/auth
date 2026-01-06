module OnboardingScenarios
  class Pyramid < Base
    def self.slug = "pyramid"

    def title
      "Join the Pyramid!"
    end

    def form_fields
      [ :first_name, :last_name, :primary_email, :birthday, :country ]
    end

    def accepts_adults = true

    def should_create_slack? = false

    def next_action = :home
  end
end
