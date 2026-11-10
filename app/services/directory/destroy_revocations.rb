# frozen_string_literal: true

module Directory
  # Revocation payloads for a person or entitlement that's about to be deleted (the rebuild
  # diff can't resolve them afterwards). Reads effective_memberships unscoped: a membership
  # that lapsed but hasn't been swept yet was never revoked, so its holder still has tokens.
  module DestroyRevocations
    module_function

    def for_entitlement(collection)
      return [] unless collection.entitlement?

      app_ids = collection.affected_app_ids
      return [] if app_ids.empty?

      person_ids = Directory::EffectiveMembership.unscoped.where(collection_id: collection.id).select(:person_id)
      Directory::Person.where(id: person_ids).includes(:identity).map { |person| person.revocation_entry(app_ids) }
    end

    def for_person(person)
      entitlement_ids = Directory::EffectiveMembership.unscoped
        .where(person_id: person.id)
        .joins(:collection)
        .where(directory_collections: { kind: "entitlement" })
        .pluck(:collection_id)
      return [] if entitlement_ids.empty?

      app_ids = Directory::Collection.affected_app_ids(entitlement_ids)
      return [] if app_ids.empty?

      [ person.revocation_entry(app_ids) ]
    end
  end
end
