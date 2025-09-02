# == Schema Information
#
# Table name: backend_organizer_positions
#
#  id              :bigint           not null, primary key
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  backend_user_id :bigint           not null
#  program_id      :bigint           not null
#
# Indexes
#
#  index_backend_organizer_positions_on_backend_user_id  (backend_user_id)
#  index_backend_organizer_positions_on_program_id       (program_id)
#
# Foreign Keys
#
#  fk_rails_...  (backend_user_id => backend_users.id)
#  fk_rails_...  (program_id => oauth_applications.id)
#
class Backend::OrganizerPosition < ApplicationRecord
  belongs_to :program, class_name: "Program", foreign_key: :program_id
  belongs_to :backend_user, class_name: "Backend::User"

  # Ensure a backend user can only have one organizer position per program
  validates :backend_user_id, uniqueness: { scope: :program_id }
  validates :program_id, presence: true
  validates :backend_user_id, presence: true
end
