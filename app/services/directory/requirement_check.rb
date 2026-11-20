# frozen_string_literal: true

module Directory
  class RequirementCheck
    # any-of; true when the app has no requirements. only checked at /oauth/authorize:
    # issued tokens aren't re-checked, losing access revokes them instead.
    #
    # uncached on purpose: prod's cache is per container, so other replicas would keep
    # admitting non-members after a requirement is added.

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
