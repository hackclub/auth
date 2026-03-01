class CreateProgramCollaborators < ActiveRecord::Migration[8.0]
  def change
    create_table :program_collaborators do |t|
      t.references :program, null: false, foreign_key: { to_table: :oauth_applications }
      t.references :identity, null: false, foreign_key: true
      t.timestamps
    end

    add_index :program_collaborators, [:program_id, :identity_id], unique: true
  end
end
