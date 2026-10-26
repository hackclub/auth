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
        ) || Directory::Membership.find_by(
          collection: collection,
          member_group_id: Directory::Membership.where(member_person: person).select(:collection_id)
        )
        membership&.destroy!
        Directory::Rebuild.call(cause: "preview")

        after = Directory::EffectiveMembership.where(person_id: person.id).pluck(:collection_id).to_set
        lost_ids = before - after
        kept_ids = after

        lost = Directory::Collection.where(id: lost_ids).pluck(:name)
        result = { loses: lost, keeps_count: kept_ids.size }

        raise ActiveRecord::Rollback
      end

      result || { loses: [], keeps_count: 0 }
    end

    # Human-readable summary
    def self.removal_summary(person:, collection:)
      data = removal(person: person, collection: collection)
      return nil if data[:loses].empty?

      if data[:loses].size <= 3
        "will lose: #{data[:loses].join(', ')}"
      else
        "will lose #{data[:loses].size} memberships including #{data[:loses].first(2).join(', ')}"
      end
    end
  end
end
