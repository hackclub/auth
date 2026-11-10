# frozen_string_literal: true

module Directory
  class Person < ApplicationRecord
    include PublicIdentifiable
    set_public_id_prefix "dper"
    include PublicActivity::Model

    tracked owner: ->(controller, _model) { controller&.try(:user_for_public_activity) },
            params: {
              name: ->(_c, model) { model.identity&.full_name },
              email: ->(_c, model) { model.identity&.primary_email }
            }

    belongs_to :identity
    belongs_to :created_by, class_name: "Identity", foreign_key: :created_by_identity_id, optional: true

    has_many :memberships, class_name: "Directory::Membership", foreign_key: :member_person_id, dependent: :destroy
    has_many :effective_memberships, class_name: "Directory::EffectiveMembership", dependent: :delete_all
    has_many :effective_grants, class_name: "Directory::EffectiveGrant", dependent: :delete_all

    validates :identity_id, uniqueness: true
    validate :identity_not_deleted, on: :create

    delegate :full_name, :primary_email, :locked?, to: :identity

    def to_param = public_id

    scope :locked, -> { joins(:identity).where.not(identities: { locked_at: nil }) }
    scope :active, -> { joins(:identity).where(identities: { locked_at: nil, deleted_at: nil }) }

    scope :search, ->(term) {
      term = term.to_s.strip
      return none if term.blank?
      like = ->(v) { "%#{ActiveRecord::Base.sanitize_sql_like(v)}%" }
      first, rest = term.split(/\s+/, 2)
      sql = "identities.first_name ILIKE :q OR identities.last_name ILIKE :q OR identities.primary_email ILIKE :q"
      # "Jane Doe": first word against first_name, the rest against last_name
      sql += " OR (identities.first_name ILIKE :first AND identities.last_name ILIKE :rest)" if rest
      joins(:identity).where(sql, q: like.(term), first: like.(first), rest: like.(rest.to_s))
    }

    # called inside open transactions, so the insert gets a savepoint: a lost race rolls
    # back only that, and the lookup after it still runs in a live transaction
    def self.find_or_create_for_identity!(identity, created_by:)
      find_by(identity: identity) || transaction(requires_new: true) do
        create!(identity: identity, created_by_identity_id: created_by.id)
      end
    rescue ActiveRecord::RecordNotUnique
      find_by!(identity: identity)
    end

    # from the table, not the caller's (possibly stale) identity object: a GDPR deletion
    # that committed while this request waited on the directory lock must win
    private def identity_not_deleted
      errors.add(:identity, "has been deleted") unless Identity.where(id: identity_id).exists?
    end

    # for "member of X (via Y)"
    def memberships_with_via_path
      all_effective = effective_memberships.includes(:collection).order("directory_collections.name")
      direct_ids = memberships.active.pluck(:collection_id).to_set

      indirect_ids = all_effective.reject { |em| direct_ids.include?(em.collection_id) }.map(&:collection_id)
      via_paths = Directory::Closure.batch_via_paths(direct_ids, indirect_ids)

      all_effective.map do |em|
        if direct_ids.include?(em.collection_id)
          { collection: em.collection, direct: true, via_path: [] }
        else
          { collection: em.collection, direct: false, via_path: via_paths[em.collection_id] || [] }
        end
      end
    end

    # { app => [exposure, ...] }
    def app_exposures
      ent_ids = effective_memberships.joins(:collection)
        .where(directory_collections: { kind: "entitlement" }).pluck(:collection_id)
      return {} unless ent_ids.any?
      exposures = Directory::Exposure.includes(:app, :entitlement).where(entitlement_id: ent_ids).to_a
      claims = Directory::Exposure.claim_pairs(app_ids: exposures.map(&:app_id), identity_ids: [ identity_id ])
      exposures.select { |exp| claims.include?([ exp.app_id, identity_id ]) }.group_by(&:app)
    end

    # entitlement_ids: what was lost, so AfterChangeJob can tell whether the loss still
    # stands. omit when it's permanent (person or collection deleted).
    def revocation_entry(app_ids, entitlement_ids: nil)
      entry = { identity_id: identity_id, email: primary_email, app_ids: app_ids }
      entry[:entitlement_ids] = entitlement_ids if entitlement_ids
      entry
    end

    def revocation_data
      entitlement_ids = effective_memberships
        .joins(:collection)
        .where(directory_collections: { kind: "entitlement" })
        .pluck(:collection_id)
      return [] if entitlement_ids.empty?

      app_ids = Directory::Collection.revocation_app_ids(entitlement_ids, [ identity_id ])[identity_id]
      app_ids.any? ? [ revocation_entry(app_ids) ] : []
    end
  end
end
