# frozen_string_literal: true

module Directory
  class EffectiveGrant < ApplicationRecord
    self.primary_key = [ :person_id, :target_collection_id, :permission ]

    default_scope { where("directory_effective_grants.expires_at IS NULL OR directory_effective_grants.expires_at > NOW()") }

    belongs_to :person, class_name: "Directory::Person"
    belongs_to :target_collection, class_name: "Directory::Collection"

    def readonly? = true
  end
end
