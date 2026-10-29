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

    validates :claim_name, presence: true
    validates :app_id, uniqueness: { scope: :entitlement_id }
    validates :claim_name, uniqueness: { scope: :app_id }
    validate :entitlement_must_be_entitlement

    private

    def entitlement_must_be_entitlement
      return unless entitlement

      errors.add(:entitlement, "must be an entitlement") unless entitlement&.entitlement?
    end
  end
end
