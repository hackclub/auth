class AddSlackDmChannelIdToIdentities < ActiveRecord::Migration[8.0]
  def change
    add_column :identities, :slack_dm_channel_id, :string
  end
end
