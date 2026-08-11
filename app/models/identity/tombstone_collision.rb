# frozen_string_literal: true

class Identity::TombstoneCollision < ApplicationRecord
  belongs_to :identity
  belongs_to :deletion

  validates :deletion_id, uniqueness: { scope: :identity_id }
end
