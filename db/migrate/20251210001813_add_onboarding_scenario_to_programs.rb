class AddOnboardingScenarioToPrograms < ActiveRecord::Migration[8.0]
  def change
    add_column :oauth_applications, :onboarding_scenario, :string
  end
end
