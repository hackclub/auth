# frozen_string_literal: true

module Directory
  class Consequence
    # For each person membership in a collection, computes what they'd lose if removed.
    # Uses the closure table to find which ancestor collections the person reaches through
    # this collection, then checks if they have an alternate path. Returns { membership_id =>
    # "will lose: X, Y, Z" } for display in the UI next to the remove button.
    def self.batch_removal_summaries(memberships:, collection:)
      person_ids = memberships.filter_map(&:member_person_id).uniq
      return {} if person_ids.empty?

      target_ancestor_ids = Directory::Closure
        .where(descendant_id: collection.id)
        .pluck(:ancestor_id)
      return {} if target_ancestor_ids.empty?

      target_set = target_ancestor_ids.to_set

      rows = Directory::Membership
        .joins("INNER JOIN directory_closure ON directory_closure.descendant_id = directory_memberships.collection_id")
        .where(member_person_id: person_ids)
        .where.not(collection_id: collection.id)
        .where(directory_closure: { ancestor_id: target_ancestor_ids })
        .distinct
        .pluck(:member_person_id, "directory_closure.ancestor_id")

      still_reachable = {}
      rows.each do |pid, aid|
        (still_reachable[pid] ||= Set.new) << aid
      end

      all_lost_ids = Set.new
      losses_by_membership = {}

      memberships.each do |m|
        next unless m.member_person_id
        reachable = still_reachable[m.member_person_id] || Set.new
        lost_ids = target_set - reachable
        next if lost_ids.empty?
        all_lost_ids.merge(lost_ids)
        losses_by_membership[m.id] = lost_ids
      end

      return {} if losses_by_membership.empty?

      names = Directory::Collection.where(id: all_lost_ids.to_a).pluck(:id, :name).to_h

      losses_by_membership.transform_values do |lost_ids|
        format_losses(lost_ids.map { |id| names[id] }.compact.sort)
      end
    end

    def self.format_losses(names)
      if names.size <= 3
        "will lose: #{names.join(', ')}"
      else
        "will lose #{names.size} memberships including #{names.first(2).join(', ')}"
      end
    end
    private_class_method :format_losses
  end
end
