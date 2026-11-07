# frozen_string_literal: true

module Directory
  # Read-only model over the transitive closure table. Each row says "ancestor_id can reach
  # descendant_id in `depth` hops through group nesting." Written exclusively by Rebuild.
  class Closure < ApplicationRecord
    self.table_name = "directory_closure"
    self.primary_key = [ :ancestor_id, :descendant_id ]

    belongs_to :ancestor, class_name: "Directory::Collection"
    belongs_to :descendant, class_name: "Directory::Collection"

    def readonly? = true

    # For a set of indirect memberships (ancestor_ids), find which direct group membership
    # (from direct_collection_ids) provides the shortest path to each. Returns
    # { ancestor_id => [via_collection] }. Used by memberships_with_via_path to show "via X."
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

    # Single-ancestor version of batch_via_paths. Currently unused (batch version preferred).
    def self.via_path(direct_collection_ids, ancestor_id)
      link = where(ancestor_id: ancestor_id)
        .where(descendant_id: direct_collection_ids.to_a)
        .where.not(descendant_id: ancestor_id)
        .order(:depth)
        .first
      return [] unless link

      child = Directory::Collection.find_by(id: link.descendant_id)
      child ? [ child ] : []
    end
  end
end
