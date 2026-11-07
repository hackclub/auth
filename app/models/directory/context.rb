# frozen_string_literal: true

module Directory
  # Pundit authorization context for directory controllers. Wraps the current user's identity,
  # directory person, and admin status. Provides can?/can_any? for permission checks against
  # the effective_grants table, with an optional preload_grants! to batch all grants into memory.
  class Context
    attr_reader :identity, :person, :admin

    def initialize(identity:, person:, admin:)
      @identity = identity
      @person = person
      @admin = admin
    end

    def admin? = !!@admin

    # Does this user hold `permission` on `collection`? Uses the in-memory cache if preloaded.
    def can?(permission, collection)
      return true if admin?
      return false unless person

      if @grants_cache
        @grants_cache.include?([ collection.id, permission.to_s ])
      else
        Directory::EffectiveGrant.exists?(
          person_id: person.id,
          target_collection_id: collection.id,
          permission: permission.to_s
        )
      end
    end

    def can_any?(permissions, collection)
      return true if admin?
      return false unless person

      perms = permissions.map(&:to_s)
      if @grants_cache
        perms.any? { |p| @grants_cache.include?([ collection.id, p ]) }
      else
        Directory::EffectiveGrant.where(
          person_id: person.id,
          target_collection_id: collection.id,
          permission: perms
        ).exists?
      end
    end

    def has_any_grants?
      return true if admin?
      return false unless person

      if @grants_cache
        @grants_cache.any?
      else
        Directory::EffectiveGrant.where(person_id: person.id).exists?
      end
    end

    # Loads all (target_collection_id, permission) pairs into a Set for O(1) lookups.
    # Called once per request in BaseController. Turns N per-collection queries into 1.
    def preload_grants!
      return self unless person

      @grants_cache = Directory::EffectiveGrant
        .where(person_id: person.id)
        .pluck(:target_collection_id, :permission)
        .to_set
      self
    end
  end
end
