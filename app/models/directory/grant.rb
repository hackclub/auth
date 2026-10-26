module Directory
  class Grant < ApplicationRecord

    has_paper_trail
    include PublicActivity::Model
    tracked owner: ->(controller, _model) { controller&.try(:user_for_public_activity) }

    belongs_to :grantee_group, class_name: "Directory::Collection"
    belongs_to :target_collection, class_name: "Directory::Collection"
    belongs_to :created_by, class_name: "Identity", foreign_key: :created_by_identity_id, optional: true

    validates :permission, inclusion: { in: %w[view manage_members expose] }

    validate :grantee_must_be_group
    validate :recursive_requires_group_target, if: -> { recursive? }

    private

    def grantee_must_be_group
      return unless grantee_group

      unless grantee_group.kind == "group"
        errors.add(:grantee_group, "must be a group")
      end
    end

    def recursive_requires_group_target
      return unless target_collection

      unless target_collection.kind == "group"
        errors.add(:target_collection, "must be a group when grant is recursive")
      end
    end
  end
end
