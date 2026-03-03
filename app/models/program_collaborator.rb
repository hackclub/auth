# frozen_string_literal: true

class ProgramCollaborator < ApplicationRecord
  include AASM

  belongs_to :program
  belongs_to :identity, optional: true

  validates :invited_email, presence: true, 'valid_email_2/email': true
  validates :invited_email, uniqueness: { scope: :program_id, conditions: -> { visible } }
  validates :identity_id, uniqueness: { scope: :program_id, conditions: -> { visible } }, allow_nil: true

  scope :visible, -> { where(status: %w[pending accepted]) }

  aasm column: :status, timestamps: true do
    state :pending, initial: true
    state :accepted
    state :declined
    state :cancelled
    state :removed

    event :accept do
      transitions from: :pending, to: :accepted
    end

    event :decline do
      transitions from: :pending, to: :declined
    end

    event :cancel do
      transitions from: :pending, to: :cancelled
    end

    event :remove do
      transitions from: %i[pending accepted], to: :removed
    end
  end
end
