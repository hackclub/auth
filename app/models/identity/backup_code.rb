class Identity::BackupCode < ApplicationRecord
  has_paper_trail

  has_secure_password :code

  include AASM

  belongs_to :identity

  validates :code_digest, presence: true

  aasm do
    state :previewed, initial: true
    state :active
    state :used
    state :discarded

    event :mark_active do
      transitions from: :previewed, to: :active
    end
    event :mark_used do
      transitions from: :active, to: :used

      after do
        identity.create_activity :use_backup_code, owner: identity, recipient: identity
        # TODO: write this mailer
        # User::BackupCodeMailer.with(user_id: user.id).code_used.deliver_now
      end
    end
    event :mark_discarded do
      transitions from: :active, to: :discarded
    end
  end
end
