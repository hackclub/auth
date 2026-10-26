module Directory
  class EffectiveGrant < ApplicationRecord
    self.primary_key = [:person_id, :target_collection_id, :permission]

    belongs_to :person, class_name: "Directory::Person"
    belongs_to :target_collection, class_name: "Directory::Collection"

    def readonly? = true
  end
end
