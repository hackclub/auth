class AddOnboardingFlowStartedToIdentities < ActiveRecord::Migration[8.0]
  def change
    add_column :identities, :onboarding_flow_started_at, :datetime

    reversible do |dir|
      dir.up do
        execute <<~SQL
          UPDATE identities
          SET onboarding_flow_started_at = created_at
          WHERE promote_click_count > 0
        SQL
      end
    end
  end
end
