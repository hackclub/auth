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
    has_many :effective_collections, through: :effective_memberships, source: :collection

    validates :identity_id, uniqueness: true

    delegate :full_name, :primary_email, :locked?, to: :identity

    def to_param = public_id

    scope :locked, -> { joins(:identity).where.not(identities: { locked_at: nil }) }
    scope :active, -> { joins(:identity).where(identities: { locked_at: nil, deleted_at: nil }) }

    scope :search, ->(term) {
      return none if term.blank?
      like = "%#{ActiveRecord::Base.sanitize_sql_like(term)}%"
      joins(:identity).where(
        "identities.first_name ILIKE :q OR identities.last_name ILIKE :q OR identities.primary_email ILIKE :q",
        q: like
      )
    }

    def self.find_or_create_for_identity!(identity, created_by:)
      find_or_create_by!(identity: identity) do |p|
        p.created_by_identity_id = created_by.id
      end
    rescue ActiveRecord::RecordNotUnique
      find_by!(identity: identity)
    end

    # Returns all effective memberships annotated with whether they're direct or inherited,
    # and for inherited ones, which direct group membership provides the path. Used on
    # person#show, /directory/me, and view_as to show "member of X (via Y)."
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

    # Which apps this person can reach via entitlement memberships.
    # Returns { app => [exposure, ...] } for the "because" column on person/my-access pages.
    def app_exposures
      ent_ids = effective_memberships.joins(:collection)
        .where(directory_collections: { kind: "entitlement" }).pluck(:collection_id)
      return {} unless ent_ids.any?
      Directory::Exposure.includes(:app, :entitlement)
        .where(entitlement_id: ent_ids).group_by(&:app)
    end

    # entitlement_ids: which entitlements were lost, so AfterChangeJob can tell whether the
    # loss still stands when it runs. Omit when the loss is permanent (person/collection deleted).
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

      app_ids = Directory::Collection.affected_app_ids(entitlement_ids)
      return [] if app_ids.empty?

      [ revocation_entry(app_ids) ]
    end
  end
end
