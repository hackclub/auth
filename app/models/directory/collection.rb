# frozen_string_literal: true

module Directory
  class Collection < ApplicationRecord
    include PublicIdentifiable
    set_public_id_prefix "dcol"
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
             class_name: "Directory::Membership", foreign_key: :member_group_id, dependent: :destroy
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
    def direct_member_count
      has_attribute?(:preloaded_direct_count) ? preloaded_direct_count : memberships.active.count
    end

    def effective_member_count
      has_attribute?(:preloaded_effective_count) ? preloaded_effective_count : effective_memberships.count
    end

    def exposure_count
      has_attribute?(:preloaded_exposure_count) ? preloaded_exposure_count : Directory::Exposure.where(entitlement_id: id).count
    end

    # Which apps care about these entitlements? An app "cares" if it has an exposure
    # (OIDC claim) or a requirement (login gate) wired to the entitlement. Flat array.
    def self.affected_app_ids(entitlement_ids)
      affected_app_ids_by_entitlement(entitlement_ids).values.flatten.uniq
    end

    # Same as above but preserves the per-entitlement mapping: { entitlement_id => [app_id, ...] }.
    # Used by Rebuild to build per-person revocation payloads.
    def self.affected_app_ids_by_entitlement(entitlement_ids)
      result = Hash.new { |h, k| h[k] = Set.new }
      Directory::Exposure.where(entitlement_id: entitlement_ids).pluck(:entitlement_id, :app_id).each { |eid, aid| result[eid] << aid }
      Directory::AppRequirement.where(entitlement_id: entitlement_ids).pluck(:entitlement_id, :app_id).each { |eid, aid| result[eid] << aid }
      result.transform_values(&:to_a)
    end

    def affected_app_ids
      self.class.affected_app_ids(id)
    end

    # Everything a recursive grant covers once it flows down into this collection: this
    # collection plus every sub-group below it, never entering a protected one, at most
    # MAX_DEPTH levels deep. Empty when this collection is protected, since recursion can't
    # enter it at all. One query. The walk mirrors GraphQueries.create_effective_grants
    # (keep the two in step); memberships#create uses it to see what nesting this under a
    # group would extend that group's recursive grants into.
    def recursive_grant_reach
      self.class.where(<<~SQL.squish, id: id, max_depth: Directory::MAX_DEPTH)
        directory_collections.id IN (
          WITH RECURSIVE reach(collection_id, depth) AS (
            SELECT id, 0 FROM directory_collections WHERE id = :id AND protected = false
            UNION ALL
            SELECT m.member_group_id, r.depth + 1
            FROM reach r
            INNER JOIN directory_memberships m ON m.collection_id = r.collection_id
            WHERE m.member_group_id IS NOT NULL
              AND (m.expires_at IS NULL OR m.expires_at > NOW())
              AND r.depth < :max_depth
              AND NOT EXISTS (
                SELECT 1 FROM directory_collections dc
                WHERE dc.id = m.member_group_id AND dc.protected = true
              )
          )
          SELECT collection_id FROM reach
        )
      SQL
    end
  end
end
