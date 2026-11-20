# frozen_string_literal: true

module Directory
  # "ancestor_id reaches descendant_id in `depth` hops". only Rebuild writes it.
  class Closure < ApplicationRecord
    self.table_name = "directory_closure"
    self.primary_key = [ :ancestor_id, :descendant_id ]

    belongs_to :ancestor, class_name: "Directory::Collection"
    belongs_to :descendant, class_name: "Directory::Collection"

    def readonly? = true

    # { ancestor_id => [collection, collection, ...] }: the full chain from the person's
    # direct group up to the ancestor. e.g. for HQ when person is in Gap Years:
    # { hq_id => [Gap Years, Full-timers, HQ] }
    def self.batch_via_paths(direct_collection_ids, ancestor_ids)
      return {} if direct_collection_ids.empty? || ancestor_ids.empty?

      # find the shallowest direct group reaching each ancestor
      rows = where(ancestor_id: ancestor_ids)
        .where(descendant_id: direct_collection_ids.to_a)
        .where.not("ancestor_id = descendant_id")
        .order(:depth)

      best_leaf = {}
      rows.each do |row|
        best_leaf[row.ancestor_id] ||= row.descendant_id
      end

      return {} if best_leaf.empty?

      # for each (ancestor, leaf) pair, walk the chain via the closure table
      # closure has (ancestor, descendant, depth) for every pair in the tree
      all_chain_ids = Set.new
      chains = {}
      best_leaf.each do |ancestor_id, leaf_id|
        # get every node between ancestor and leaf: nodes that are descendants
        # of ancestor AND ancestors of leaf
        intermediates = where(ancestor_id: ancestor_id)
          .where(descendant_id: where(ancestor_id: leaf_id).select(:ancestor_id))
          .where.not("ancestor_id = descendant_id AND depth = 0")
          .order(:depth)
          .pluck(:descendant_id)
        chain = ([ leaf_id ] + intermediates).uniq
        chains[ancestor_id] = chain
        all_chain_ids.merge(chain)
      end

      collections = Directory::Collection.where(id: all_chain_ids.to_a).index_by(&:id)

      chains.transform_values { |ids| ids.filter_map { |id| collections[id] } }
    end
  end
end
