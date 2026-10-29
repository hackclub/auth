# frozen_string_literal: true

module Directory
  class Collection < ApplicationRecord
    has_paper_trail
    include PublicActivity::Model
    tracked owner: ->(controller, _model) { controller&.try(:user_for_public_activity) },
            params: {
              name: ->(_c, model) { model.name },
              kind: ->(_c, model) { model.kind },
              slug: ->(_c, model) { model.slug },
              changes: ->(_c, model) {
                c = model.saved_changes.except("created_at")
                c.present? ? c.to_h { |k, v| [ k, v.map(&:to_s) ] } : nil
              }
            }

    def self.policy_class = Directory::CollectionPolicy

    belongs_to :created_by, class_name: "Identity", foreign_key: :created_by_identity_id, optional: true

    has_many :memberships, foreign_key: :collection_id, dependent: :destroy
    has_many :member_people_memberships, -> { where.not(member_person_id: nil) },
             class_name: "Directory::Membership", foreign_key: :collection_id
    has_many :member_group_memberships, -> { where.not(member_group_id: nil) },
             class_name: "Directory::Membership", foreign_key: :collection_id
    has_many :direct_people, through: :member_people_memberships, source: :member_person
    has_many :direct_groups, through: :member_group_memberships, source: :member_group

    has_many :effective_memberships, dependent: :delete_all
    has_many :effective_people, through: :effective_memberships, source: :person

    has_many :grants_as_target, class_name: "Directory::Grant", foreign_key: :target_collection_id, dependent: :destroy
    has_many :grants_as_grantee, class_name: "Directory::Grant", foreign_key: :grantee_group_id, dependent: :destroy

    has_many :parent_memberships, -> { where.not(member_group_id: nil) },
             class_name: "Directory::Membership", foreign_key: :member_group_id
    has_many :parent_collections, through: :parent_memberships, source: :collection

    enum :kind, { group: "group", entitlement: "entitlement" }, scopes: false, instance_methods: false

    scope :groups, -> { where(kind: "group") }
    scope :entitlements, -> { where(kind: "entitlement") }

    validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ }
    validates :name, presence: true
    validates :kind, presence: true

    def group? = kind == "group"
    def entitlement? = kind == "entitlement"
    def to_param = slug
    def direct_member_count = memberships.count
    def effective_member_count = effective_memberships.count
  end
end
