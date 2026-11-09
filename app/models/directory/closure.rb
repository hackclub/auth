# frozen_string_literal: true

module Directory
  # "ancestor_id reaches descendant_id in `depth` hops". only Rebuild writes it.
  class Closure < ApplicationRecord
    self.table_name = "directory_closure"
    self.primary_key = [ :ancestor_id, :descendant_id ]

    belongs_to :ancestor, class_name: "Directory::Collection"
    belongs_to :descendant, class_name: "Directory::Collection"

    def readonly? = true

    # { ancestor_id => [via_collection] }: the direct group giving the shortest path to each
    def self.batch_via_paths(direct_collection_ids, ancestor_ids)
      return {} if direct_collection_ids.empty? || ancestor_ids.empty?

      rows = where(ancestor_id: ancestor_ids)
        .where(descendant_id: direct_collection_ids.to_a)
        .where.not("ancestor_id = descendant_id")
        .order(:depth)

      best_by_ancestor = {}
      rows.each do |row|
        best_by_ancestor[row.ancestor_id] ||= row.descendant_id
      end

      collections = Directory::Collection.where(id: best_by_ancestor.values.uniq).index_by(&:id)

      best_by_ancestor.transform_values { |desc_id| collections[desc_id] ? [ collections[desc_id] ] : [] }
    end
  end
end
