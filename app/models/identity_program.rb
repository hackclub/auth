# == Schema Information
#
# Table name: identity_programs
#
#  id          :bigint           not null, primary key
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  identity_id :bigint           not null
#  program_id  :bigint           not null
#
# Indexes
#
#  index_identity_programs_on_identity_id                 (identity_id)
#  index_identity_programs_on_identity_id_and_program_id  (identity_id,program_id) UNIQUE
#  index_identity_programs_on_program_id                  (program_id)
#
# Foreign Keys
#
#  fk_rails_...  (identity_id => identities.id)
#  fk_rails_...  (program_id => programs.id)
#
class IdentityProgram < ApplicationRecord
  belongs_to :identity
  belongs_to :program

  validates :identity_id, uniqueness: { scope: :program_id }
end
