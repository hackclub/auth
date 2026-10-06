class AddPasskeyPromptDismissedAtToIdentities < ActiveRecord::Migration[8.0]
  def change
    add_column :identities, :passkey_prompt_dismissed_at, :datetime
  end
end
