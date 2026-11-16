# frozen_string_literal: true

module Directory
  class AppRequirement < ApplicationRecord
    self.primary_key = %i[app_id entitlement_id]

    belongs_to :app, class_name: "Program"
    belongs_to :entitlement, class_name: "Directory::Collection"

    validate :entitlement_must_be_entitlement

    private

    def entitlement_must_be_entitlement
      return unless entitlement

      errors.add(:entitlement, "must be an entitlement") unless entitlement&.entitlement?
    end
  end
end
