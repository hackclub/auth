# frozen_string_literal: true

class ProgramCollaborator < ApplicationRecord
  include AASM

  belongs_to :program
  belongs_to :identity, optional: true

  validates :invited_email, presence: true
  validates :invited_email, uniqueness: { scope: :program_id, conditions: -> { visible } }
  validates :identity_id, uniqueness: { scope: :program_id }, allow_nil: true

  scope :visible, -> { where(status: %w[pending accepted]) }

  aasm column: :status, timestamps: true do
    state :pending, initial: true
    state :accepted
    state :declined
    state :cancelled

    event :accept do
      transitions from: :pending, to: :accepted
    end

    event :decline do
      transitions from: :pending, to: :declined
    end

    event :cancel do
      transitions from: :pending, to: :cancelled
    end
  end
end
