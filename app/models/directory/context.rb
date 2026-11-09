# frozen_string_literal: true

module Directory
  class Context
    attr_reader :identity, :person, :admin

    def initialize(identity:, person:, admin:)
      @identity = identity
      @person = person
      @admin = admin
    end

    def admin? = !!@admin

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
