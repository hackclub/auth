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

    has_many :effective_memberships, dependent: :delete_all
    has_many :effective_people, through: :effective_memberships, source: :person

    # destroyed (not left to the FK cascade) so each one leaves the same audit trail as an unwire
    has_many :exposures, class_name: "Directory::Exposure", foreign_key: :entitlement_id, dependent: :destroy
    has_many :grants_as_target, class_name: "Directory::Grant", foreign_key: :target_collection_id, dependent: :destroy
    has_many :grants_as_grantee, class_name: "Directory::Grant", foreign_key: :grantee_group_id, dependent: :destroy

    has_many :parent_memberships, -> { where.not(member_group_id: nil) },
             class_name: "Directory::Membership", foreign_key: :member_group_id, dependent: :destroy

    enum :kind, { group: "group", entitlement: "entitlement" }, scopes: false, instance_methods: false

    scope :groups, -> { where(kind: "group") }
    scope :entitlements, -> { where(kind: "entitlement") }

    # /directory/collections/new is the new-collection form
    RESERVED_SLUGS = %w[new].freeze

    validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ },
                     exclusion: { in: RESERVED_SLUGS, message: "is reserved" }
    validates :name, presence: true
    validates :kind, presence: true
    validate :slug_kept_while_saml_uses_it, on: :update, if: -> { entitlement? && slug_changed? }

    # config/saml.yml names entitlements by slug; losing one would lock everyone out of an
    # SP that requires it, or quietly drop it from the groups the SP is sent.
    before_destroy :ensure_no_saml_service_provider_uses_it, if: :entitlement?, prepend: true

    def group? = kind == "group"
    def entitlement? = kind == "entitlement"
    def to_param = slug
    # people only, to match effective_member_count
    def direct_member_count
      has_attribute?(:preloaded_direct_count) ? preloaded_direct_count : member_people_memberships.active.count
    end

    def effective_member_count
      return preloaded_effective_count if has_attribute?(:preloaded_effective_count)

      effective_memberships.where("expires_at IS NULL OR expires_at > ?", Time.current).count
    end

    def exposure_count
      has_attribute?(:preloaded_exposure_count) ? preloaded_exposure_count : Directory::Exposure.live.where(entitlement_id: id).count
    end

    # apps with an exposure or a requirement on any of these entitlements
    def self.affected_app_ids(entitlement_ids)
      affected_app_ids_by_entitlement(entitlement_ids).values.flatten.uniq
    end

    def self.affected_app_ids_by_entitlement(entitlement_ids)
      result = Hash.new { |h, k| h[k] = Set.new }
      Directory::Exposure.where(entitlement_id: entitlement_ids).pluck(:entitlement_id, :app_id).each { |eid, aid| result[eid] << aid }
      Directory::AppRequirement.where(entitlement_id: entitlement_ids).pluck(:entitlement_id, :app_id).each { |eid, aid| result[eid] << aid }
      result.transform_values(&:to_a)
    end

    def affected_app_ids
      self.class.affected_app_ids(id)
    end

    # { identity_id => app_ids } a permanent loss of these entitlements should revoke: every
    # app requiring one, and every app exposing one whose groups claim reaches that person
    def self.revocation_app_ids(entitlement_ids, identity_ids)
      required = Directory::AppRequirement.where(entitlement_id: entitlement_ids).distinct.pluck(:app_id)
      exposed = Directory::Exposure.where(entitlement_id: entitlement_ids).distinct.pluck(:app_id)
      claims = Directory::Exposure.claim_pairs(app_ids: exposed, identity_ids: identity_ids)

      identity_ids.uniq.to_h do |identity_id|
        [ identity_id, (required + exposed.select { |app_id| claims.include?([ app_id, identity_id ]) }).uniq ]
      end
    end

    # what a recursive grant covers once it flows into this collection: itself plus every
    # unprotected sub-group, to MAX_DEPTH. mirrors GraphQueries.create_effective_grants; keep
    # the two in step.
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

    private

    def saml_service_providers_using(slug) = SAMLService::Access.service_providers_using_entitlement(slug)

    def slug_kept_while_saml_uses_it
      sps = saml_service_providers_using(slug_was)
      errors.add(:slug, :used_by_saml, apps: sps.map { |sp| sp[:friendly_name] }.to_sentence) if sps.any?
    end

    def ensure_no_saml_service_provider_uses_it
      sps = saml_service_providers_using(slug)
      return if sps.empty?

      errors.add(:base, :used_by_saml, apps: sps.map { |sp| sp[:friendly_name] }.to_sentence)
      throw :abort
    end
  end
end
