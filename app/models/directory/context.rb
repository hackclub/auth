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

      Directory::EffectiveGrant.exists?(
        person_id: person.id,
        target_collection_id: collection.id,
        permission: permission.to_s
      )
    end

    def can_any?(permissions, collection)
      return true if admin?
      return false unless person

      Directory::EffectiveGrant.where(
        person_id: person.id,
        target_collection_id: collection.id,
        permission: permissions.map(&:to_s)
      ).exists?
    end
  end
end
