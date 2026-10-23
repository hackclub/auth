module Directory
  class EffectiveMembership < ApplicationRecord
    self.table_name = "directory_effective_memberships"
    self.primary_key = [:collection_id, :person_id]

    belongs_to :collection, class_name: "Directory::Collection"
    belongs_to :person, class_name: "Directory::Person"

    def readonly? = true
  end
end
