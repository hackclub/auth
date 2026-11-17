# frozen_string_literal: true

module Directory
  class Context
    attr_reader :identity, :person, :admin

    # manage_members is a superset: if you can manage the roster you can also
    # view the collection and wire it to apps (expose)
    IMPLIED_BY_MANAGE = %w[view expose].to_set.freeze

    def initialize(identity:, person:, admin:)
      @identity = identity
      @person = person
      @admin = admin
    end

    def admin? = !!@admin

    def can?(permission, collection)
      return true if admin?
      return false unless person

      perm = permission.to_s
      if @grants_cache
        @grants_cache.include?([ collection.id, perm ]) ||
          (IMPLIED_BY_MANAGE.include?(perm) && @grants_cache.include?([ collection.id, "manage_members" ]))
      else
        perms = IMPLIED_BY_MANAGE.include?(perm) ? [ perm, "manage_members" ] : [ perm ]
        Directory::EffectiveGrant.where(
          person_id: person.id,
          target_collection_id: collection.id,
          permission: perms
        ).exists?
      end
    end

    def can_any?(permissions, collection)
      return true if admin?
      return false unless person

      perms = permissions.map(&:to_s)
      # if any requested perm is implied by manage_members, include it in the check
      perms = (perms + [ "manage_members" ]).uniq if perms.any? { |p| IMPLIED_BY_MANAGE.include?(p) }
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

    # an expose grant only matters on entitlements (groups can't be wired to apps).
    # manage_members implies expose, so check both.
    def can_expose_any_entitlement?
      return true if admin?
      return false unless person

      Directory::EffectiveGrant.joins(:target_collection)
        .where(person_id: person.id, permission: %w[expose manage_members], directory_collections: { kind: "entitlement" })
        .exists?
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
