class AddProvenanceToLoginAttempts < ActiveRecord::Migration[8.0]
  def change
    add_column :login_attempts, :provenance, :string
    add_column :login_attempts, :next_action, :string
  end
end


