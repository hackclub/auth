class AddOnboardingScenarioToIdentities < ActiveRecord::Migration[8.0]
  def change
    add_column :identities, :onboarding_scenario, :string
  end
end
