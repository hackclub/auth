# frozen_string_literal: true

module Directory
  class RequirementCheck
    # Returns true if the identity meets the app's directory requirements.
    # Returns true if the app has no requirements configured.
    def self.passes?(identity:, app:)
      requirements = Directory::AppRequirement.where(app_id: app.id)
      return true unless requirements.exists?

      person = Directory::Person.find_by(identity: identity)
      return false unless person

      required_entitlement_ids = requirements.pluck(:entitlement_id)
      # any-of: member of at least one required entitlement
      Directory::EffectiveMembership
        .where(person_id: person.id, collection_id: required_entitlement_ids)
        .exists?
    end
  end
end
