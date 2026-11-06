# frozen_string_literal: true

module Directory
  # Runs after a rebuild commits. Processes "removed" effective membership changes:
  # for each person who lost an entitlement, checks if they still qualify for each affected
  # app (via another entitlement), and revokes access if not. Deduplicates across the two
  # input sources (pre-resolved revocations + change records) to avoid double-revoking.
  class AfterChangeJob < ApplicationJob
    queue_as :default

    # revocations: pre-resolved { identity_id, email, app_ids } for entities that may be
    #   deleted by the time this job runs (person removed, collection deleted).
    # change_ids: IDs in membership_changes table for the rebuild diff.
    def perform(change_ids:, revocations: nil)
      processed = Set.new

      if revocations.present?
        revocations.each do |rev|
          rev = rev.symbolize_keys
          person = Directory::Person.find_by(identity_id: rev[:identity_id])
          rev[:app_ids].each do |app_id|
            next if person && still_has_access?(person, app_id)
            key = [ rev[:identity_id], app_id ]
            next if processed.include?(key)
            processed << key
            revoke_access(rev[:identity_id], app_id, rev[:email])
          end
        end
      end

      changes = Directory::MembershipChange.where(id: change_ids, op: "removed")

      collection_ids = changes.pluck(:collection_id).uniq
      person_ids = changes.pluck(:person_id).uniq
      collections_by_id = Directory::Collection.where(id: collection_ids).index_by(&:id)
      persons_by_id = Directory::Person.where(id: person_ids).includes(:identity).index_by(&:id)

      entitlement_ids = collections_by_id.values.select(&:entitlement?).map(&:id)
      app_ids_by_collection = Directory::Collection.affected_app_ids_by_entitlement(entitlement_ids)

      changes.each do |change|
        collection = collections_by_id[change.collection_id]
        person = persons_by_id[change.person_id]
        next unless collection&.entitlement? && person

        identity = person.identity
        app_ids = app_ids_by_collection[collection.id] || []

        app_ids.each do |app_id|
          key = [ identity.id, app_id ]
          next if processed.include?(key)
          next if still_has_access?(person, app_id)
          processed << key
          revoke_access(identity.id, app_id, identity.primary_email)
        end
      end
    end

    private

    # Does this person still meet the app's requirements via a different entitlement?
    # True if the app has no requirements, or the person holds at least one required entitlement.
    def still_has_access?(person, app_id)
      requirement_ids = requirements_for_app(app_id)
      return true if requirement_ids.empty?
      person_entitlement_ids(person).intersect?(requirement_ids.to_set)
    end

    def requirements_for_app(app_id)
      @requirements_cache ||= {}
      @requirements_cache[app_id] ||= Directory::AppRequirement.where(app_id: app_id).pluck(:entitlement_id)
    end

    def person_entitlement_ids(person)
      @person_entitlements_cache ||= {}
      @person_entitlements_cache[person.id] ||= Directory::EffectiveMembership.where(person_id: person.id).pluck(:collection_id).to_set
    end

    def app_ids_affected_by(entitlement)
      entitlement.affected_app_ids
    end

    def revoke_access(identity_id, app_id, email)
      Directory::RevokeAccess.call(identity_id: identity_id, app_id: app_id, email: email)
    end
  end
end
