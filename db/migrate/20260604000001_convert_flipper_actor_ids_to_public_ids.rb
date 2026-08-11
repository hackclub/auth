class ConvertFlipperActorIdsToPublicIds < ActiveRecord::Migration[8.0]
  def up
    execute("SELECT id, value FROM flipper_gates WHERE key = 'actors' AND value LIKE 'Identity;%'").each do |row|
      identity = Identity.find_by(id: row["value"].split(";").last)
      next unless identity

      execute("UPDATE flipper_gates SET value = #{connection.quote(identity.public_id)} WHERE id = #{row["id"]}")
    end
  end

  def down
    execute("SELECT id, value FROM flipper_gates WHERE key = 'actors' AND value LIKE 'ident!%'").each do |row|
      identity = Identity.find_by_public_id(row["value"])
      next unless identity

      execute("UPDATE flipper_gates SET value = #{connection.quote("Identity;#{identity.id}")} WHERE id = #{row["id"]}")
    end
  end
end
