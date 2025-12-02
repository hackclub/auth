class AddLastStepUpAtToIdentitySessions < ActiveRecord::Migration[8.0]
  def change
    add_column :identity_sessions, :last_step_up_at, :datetime
  end
end
