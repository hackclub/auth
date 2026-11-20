# frozen_string_literal: true

module Directory
  class Grant < ApplicationRecord
    has_paper_trail
    include PublicActivity::Model
    tracked owner: ->(controller, _model) { controller&.try(:user_for_public_activity) },
            trackable: ->(_c, model) { model.target_collection },
            params: {
              grantee_name: ->(_c, model) { model.grantee_group&.name || model.grantee_person&.full_name },
              permission: ->(_c, model) { model.permission },
              recursive: ->(_c, model) { model.recursive }
            }

    belongs_to :grantee_group, class_name: "Directory::Collection", optional: true
    belongs_to :grantee_person, class_name: "Directory::Person", optional: true
    belongs_to :target_collection, class_name: "Directory::Collection"
    belongs_to :created_by, class_name: "Identity", foreign_key: :created_by_identity_id, optional: true

    validates :permission, inclusion: { in: %w[view manage_members expose] }
    # uniqueness enforced by partial DB indexes (one per grantee lane)
    validates :permission, uniqueness: { scope: %i[grantee_group_id target_collection_id], message: "grant already exists" },
              if: -> { grantee_group_id.present? }
    validates :permission, uniqueness: { scope: %i[grantee_person_id target_collection_id], message: "grant already exists" },
              if: -> { grantee_person_id.present? }

    validate :exactly_one_grantee
    validate :grantee_group_must_be_group, if: -> { grantee_group_id.present? }
    validate :recursive_requires_group_target, if: -> { recursive? }
    validate :person_grant_cannot_be_recursive, if: -> { grantee_person_id.present? && recursive? }

    def grantee_name
      grantee_group&.name || grantee_person&.full_name
    end

    private

    def exactly_one_grantee
      has_group = grantee_group_id.present?
      has_person = grantee_person_id.present?
      errors.add(:base, "grant must have exactly one grantee (group or person)") unless has_group ^ has_person
    end

    def grantee_group_must_be_group
      return unless grantee_group
      errors.add(:grantee_group, "must be a group") unless grantee_group.kind == "group"
    end

    def recursive_requires_group_target
      return unless target_collection
      errors.add(:target_collection, "must be a group when grant is recursive") unless target_collection.kind == "group"
    end

    def person_grant_cannot_be_recursive
      errors.add(:recursive, "is not supported for person grants")
    end
  end
end
