# append-only audit trail for a case. every state transition, every
# document view, every decision — the break-glass requirement means
# reads get logged too, so this table only ever grows.
class VerificationCase::Event < ApplicationRecord
  self.table_name = "verification_case_events"

  belongs_to :verification_case
  belongs_to :actor, polymorphic: true, optional: true

  validates :key, presence: true

  # append-only: rows can be created, never mutated or deleted
  def readonly? = persisted?

  before_destroy { raise ActiveRecord::ReadOnlyRecord }

  scope :recent_first, -> { order(created_at: :desc) }
end
