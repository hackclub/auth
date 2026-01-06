class DeduplicatePrimaryEmails < ActiveRecord::Migration[8.0]
  def up
    duplicates = execute(<<~SQL).to_a
      SELECT LOWER(primary_email) AS email, array_agg(id ORDER BY created_at ASC) AS ids
      FROM identities
      WHERE deleted_at IS NULL
      GROUP BY LOWER(primary_email)
      HAVING COUNT(*) > 1
    SQL

    duplicates.each do |row|
      ids = row["ids"][1..-2].split(",").map(&:to_i) # parse PG array
      keeper_id = ids.shift # keep the oldest record

      ids.each do |dup_id|
        say "Soft-deleting duplicate identity #{dup_id} (keeping #{keeper_id}) for email #{row['email']}"
        execute("UPDATE identities SET deleted_at = NOW() WHERE id = #{dup_id}")
      end
    end
  end

  def down
  end
end
