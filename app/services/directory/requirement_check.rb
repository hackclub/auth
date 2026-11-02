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
