class LinkBackendUserToIdentity < ActiveRecord::Migration[8.0]
  def up
    add_reference :backend_users, :identity, foreign_key: true, null: true, index: false

    Backend::User.reset_column_information

    Backend::User.find_each do |user|
      if user.slack_id.present?
        identity = Identity.find_by(slack_id: user.slack_id)
        if identity
          user.update_column(:identity_id, identity.id)
        end
      end
    end

    add_index :backend_users, :identity_id
  end

  def down
    remove_reference :backend_users, :identity
  end
end
