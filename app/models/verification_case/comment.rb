# staff discussion on a case, replacing the old slack thread — reviewer
# notes, second opinions, anything that isn't a formal audit event.
class VerificationCase::Comment < ApplicationRecord
  self.table_name = "verification_case_comments"

  belongs_to :verification_case
  belongs_to :author, class_name: "Backend::User"

  validates :body, presence: true, length: { maximum: 5_000 }

  scope :chronological, -> { order(created_at: :asc) }
end
