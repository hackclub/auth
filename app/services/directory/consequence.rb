# frozen_string_literal: true

module Directory
  class Consequence
    # Preview what would change if this membership were removed.
    # Runs the actual rebuild inside a rolled-back transaction so the
    # result is authoritative, not heuristic.
    def self.removal(person:, collection:)
      before = Directory::EffectiveMembership.where(person_id: person.id).pluck(:collection_id).to_set

      result = nil
      ActiveRecord::Base.transaction do
        membership = Directory::Membership.find_by(
          collection: collection,
          member_person: person
        )
        unless membership
          descendant_ids = Directory::Closure
            .where(ancestor_id: collection.id)
            .where.not(depth: 0)
            .order(:depth)
            .pluck(:descendant_id)
          membership = Directory::Membership
            .where(collection_id: descendant_ids, member_person: person)
            .first if descendant_ids.any?
        end
        membership&.destroy!
        Directory::Rebuild.call(cause: "preview", skip_lock: true)

        after = Directory::EffectiveMembership.where(person_id: person.id).pluck(:collection_id).to_set
        lost_ids = before - after
        kept_ids = after

        lost = Directory::Collection.where(id: lost_ids).pluck(:name).sort
        result = { loses: lost, keeps_count: kept_ids.size }

        raise ActiveRecord::Rollback
      end

      result || { loses: [], keeps_count: 0 }
    end

    # Human-readable summary
    def self.removal_summary(person:, collection:)
      data = removal(person: person, collection: collection)
      return nil if data[:loses].empty?

      format_losses(data[:loses])
    end

    # Batch-compute removal summaries from the closure table directly,
    # avoiding N full rebuilds. Returns { membership_id => summary_string }.
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
