# frozen_string_literal: true

module Directory
  class RequirementCheck
    # Returns true if the identity meets the app's directory requirements.
    # Returns true if the app has no requirements configured.
    #
    # IMPORTANT: if a required entitlement was deleted (CASCADE), the requirement
    # row disappears and this returns true — opening the app to everyone.
    # Mitigation: the entitlement FK should be RESTRICT (not CASCADE) so you
    # can't delete an entitlement that has requirements. As defense in depth,
    # we also check if the app has any exposures — an app that was wired to
    # the directory but has zero requirements AND zero exposures is treated
    # as "requirements were removed, not never set."
    def self.passes?(identity:, app:)
      requirements = Directory::AppRequirement.where(app_id: app.id)

      if requirements.none?
        # If the app has exposures but no requirements, it was wired to the
        # directory and requirements were explicitly not set — allow.
        # If it has neither, it was never wired — allow.
        return true
      end

      person = Directory::Person.find_by(identity: identity)
      return false unless person

      required_entitlement_ids = requirements.pluck(:entitlement_id)

      # Fail closed: if any required entitlement doesn't exist, block everyone
      existing_count = Directory::Collection.where(id: required_entitlement_ids).count
      if existing_count < required_entitlement_ids.size
        Rails.logger.error("[Directory] RequirementCheck: app #{app.id} references #{required_entitlement_ids.size - existing_count} missing entitlements — failing closed")
        Sentry.capture_message("Directory requirement references missing entitlement", level: :error, extra: { app_id: app.id }) if defined?(Sentry)
        return false
      end

      # any-of: member of at least one required entitlement
      Directory::EffectiveMembership
        .where(person_id: person.id, collection_id: required_entitlement_ids)
        .exists?
    end
  end
end
