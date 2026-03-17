class AddStatusToProgramCollaborators < ActiveRecord::Migration[8.0]
  def change
    add_column :program_collaborators, :status, :string, default: "pending", null: false
    add_column :program_collaborators, :accepted_at, :datetime
    add_column :program_collaborators, :invited_email, :string

    # Backfill existing rows as accepted
    reversible do |dir|
      dir.up do
        ProgramCollaborator.update_all(status: "accepted", accepted_at: Time.current)
      end
    end
  end
end
