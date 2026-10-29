module Directory
  class Closure < ApplicationRecord
    self.table_name = "directory_closure"
    self.primary_key = [ :ancestor_id, :descendant_id ]

    belongs_to :ancestor, class_name: "Directory::Collection"
    belongs_to :descendant, class_name: "Directory::Collection"

    def readonly? = true

    def self.via_path(direct_collection_ids, ancestor_id)
      link = where(ancestor_id: ancestor_id)
        .where(descendant_id: direct_collection_ids.to_a)
        .where.not(descendant_id: ancestor_id)
        .order(:depth)
        .first
      return [] unless link

      child = Directory::Collection.find_by(id: link.descendant_id)
      child ? [child] : []
    end
  end
end
