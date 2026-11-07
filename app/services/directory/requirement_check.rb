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
    # Fails closed if a required entitlement is missing from the DB (logs + blocks everyone).
    # Called on every OAuth authorize, every API request, and every token refresh.
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
