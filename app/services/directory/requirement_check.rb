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
    CACHE_TTL = 5.minutes

    def self.passes?(identity:, app:)
      entitlement_ids = cached_requirement_ids(app.id)
      return true if entitlement_ids.empty?

      person = Directory::Person.find_by(identity: identity)
      return false unless person

      Directory::EffectiveMembership
        .where(person_id: person.id, collection_id: entitlement_ids)
        .exists?
    end

    def self.cached_requirement_ids(app_id)
      Rails.cache.fetch("directory/requirement_check/#{app_id}", expires_in: CACHE_TTL) do
        Directory::AppRequirement.where(app_id: app_id).pluck(:entitlement_id)
      end
    end
    private_class_method :cached_requirement_ids

    def self.bust_cache!(app_id)
      Rails.cache.delete("directory/requirement_check/#{app_id}")
    end
  end
end
