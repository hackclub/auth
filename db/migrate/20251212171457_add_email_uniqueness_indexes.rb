class AddEmailUniquenessIndexes < ActiveRecord::Migration[8.0]
  def change
    # Ensure primary_email uniqueness at DB level (case-insensitive, excluding soft-deleted)
    # Rails validation alone has TOCTTOU race conditions
    add_index :identities,
      "LOWER(primary_email)",
      unique: true,
      where: "deleted_at IS NULL",
      name: "idx_identities_unique_primary_email"

    # Note: Partial unique index for pending email change requests is not possible
    # because PostgreSQL requires immutable functions in index predicates.
    # The expires_at > NOW() condition uses a non-immutable function.
    # We handle this at the application layer by cancelling existing pending requests.
  end
end
