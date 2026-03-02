class AllowNullIdentityOnProgramCollaborators < ActiveRecord::Migration[8.0]
  def change
    change_column_null :program_collaborators, :identity_id, true
    add_index :program_collaborators, [:program_id, :invited_email], unique: true,
              where: "status IN ('pending', 'accepted')",
              name: "idx_program_collabs_on_program_email_visible"
  end
end
