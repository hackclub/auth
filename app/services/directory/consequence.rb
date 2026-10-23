# frozen_string_literal: true

module Directory
  class Consequence
    # Given a person and the collection they're being removed from,
    # returns a human sentence describing what they'll lose — or nil
    # if the removal has no downstream effect.
    def self.removal_summary(person:, collection:)
      # Count effective memberships that flow through this collection.
      # A person who is a direct member of collection C, and C is nested
      # inside parent P, would lose their effective membership in P if
      # they have no other path to P.
      #
      # For v1 we show a simpler metric: how many *other* collections
      # include this person effectively through this one. We count
      # parent collections that contain `collection` as a member group,
      # then check which of those the person would still reach via
      # another membership.

      parent_collection_ids = collection.parent_collections.pluck(:id)
      return nil if parent_collection_ids.empty?

      # Collections the person reaches effectively (excluding the one being removed)
      still_effective_ids = Directory::EffectiveMembership
        .where(person_id: person.id)
        .where.not(collection_id: collection.id)
        .pluck(:collection_id)

      lost_ids = parent_collection_ids - still_effective_ids
      return nil if lost_ids.empty?

      count = lost_ids.size
      "they are an effective member of #{count} other #{'collection'.pluralize(count)} through this one."
    end
  end
end
