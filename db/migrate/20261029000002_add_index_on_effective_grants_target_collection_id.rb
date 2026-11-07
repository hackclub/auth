class AddIndexOnEffectiveGrantsTargetCollectionId < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_index :directory_effective_grants, :target_collection_id, algorithm: :concurrently
  end
end
