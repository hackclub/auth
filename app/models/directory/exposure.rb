# frozen_string_literal: true

module Directory
  class Exposure < ApplicationRecord
    has_paper_trail
    include PublicActivity::Model
    tracked owner: ->(controller, _model) { controller&.try(:user_for_public_activity) || controller&.try(:current_identity) },
            params: {
              app_name: ->(_c, model) { model.app&.name },
              entitlement_name: ->(_c, model) { model.entitlement&.name },
              claim_name: ->(_c, model) { model.claim_name }
            }

    belongs_to :app, class_name: "Program"
    belongs_to :entitlement, class_name: "Directory::Collection"
    belongs_to :created_by, class_name: "Identity", foreign_key: :created_by_identity_id, optional: true

    validates :claim_name, presence: true,
      format: { with: /\A[a-z][a-z0-9_-]*\z/, message: "must start with a lowercase letter and contain only lowercase letters, numbers, hyphens, and underscores" }
    validates :app_id, uniqueness: { scope: :entitlement_id }
    validates :claim_name, uniqueness: { scope: :app_id }
    validate :entitlement_must_be_entitlement
    validate :app_must_request_groups, on: :create

    # an app without the groups scope never receives the claim, so its exposures are inert
    def self.live = joins(:app).where("' ' || oauth_applications.scopes || ' ' LIKE '% groups %'")

    def self.claim_names_for(person:, app:)
      where(app_id: app.id)
        .where(entitlement_id: Directory::EffectiveMembership.where(person_id: person.id).select(:collection_id))
        .pluck(:claim_name)
    end

    private

    def app_must_request_groups
      return unless app

      errors.add(:base, "this app doesn't request the groups scope, so it would never receive the claim. ask an admin to add the scope first") unless app.has_scope?(:groups)
    end

    def entitlement_must_be_entitlement
      return unless entitlement

      errors.add(:entitlement, "must be an entitlement") unless entitlement&.entitlement?
    end
  end
end
