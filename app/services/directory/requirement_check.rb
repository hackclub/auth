# frozen_string_literal: true

module Directory
  class RequirementCheck
    # Can this identity use this app? Checks the app's AppRequirement records (if any)
    # against the identity's effective entitlement memberships.
    #
    # Returns true if:
    #   - The app has no requirements (most apps — cheap early return)
    #   - The identity is in at least one required entitlement (any-of semantics)
    #
    # Only enforced at /oauth/authorize (the resource-owner authenticator in the doorkeeper
    # initializer). Tokens already issued aren't re-checked on API, userinfo or refresh
    # requests; instead, losing access revokes them — AfterChangeJob for membership changes,
    # RevokeAccess.bulk_revoke_non_passing when an app's requirement list changes.
    #
    # Deliberately uncached: prod has no shared cache store (each container gets its own
    # file store), so a cached requirement list would let other replicas keep admitting
    # non-members after a requirement is added. It's one indexed pluck per authorize.

    def self.passes?(identity:, app:)
      entitlement_ids = Directory::AppRequirement.where(app_id: app.id).pluck(:entitlement_id)
      return true if entitlement_ids.empty?

      person = Directory::Person.find_by(identity: identity)
      return false unless person

      Directory::EffectiveMembership
        .where(person_id: person.id, collection_id: entitlement_ids)
        .exists?
    end
  end
end
