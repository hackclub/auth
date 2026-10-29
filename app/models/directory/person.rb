# frozen_string_literal: true

module Directory
  class Person < ApplicationRecord
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

    scope :locked, -> { joins(:identity).where.not(identities: { locked_at: nil }) }
    scope :active, -> { joins(:identity).where(identities: { locked_at: nil, deleted_at: nil }) }

    def revocation_data
      entitlement_ids = effective_memberships
        .joins(:collection)
        .where(directory_collections: { kind: "entitlement" })
        .pluck(:collection_id)
      return [] if entitlement_ids.empty?

      app_ids = (
        Directory::Exposure.where(entitlement_id: entitlement_ids).pluck(:app_id) +
        Directory::AppRequirement.where(entitlement_id: entitlement_ids).pluck(:app_id)
      ).uniq
      return [] if app_ids.empty?

      [ { identity_id: identity_id, email: primary_email, app_ids: app_ids } ]
    end
  end
end
