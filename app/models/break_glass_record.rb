# frozen_string_literal: true

# == Schema Information
#
# Table name: break_glass_records
#
#  id                   :bigint           not null, primary key
#  accessed_at          :datetime         not null
#  automatic            :boolean          default(FALSE)
#  break_glassable_type :string           not null
#  reason               :text             not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  backend_user_id      :bigint           not null
#  break_glassable_id   :bigint           not null
#
# Indexes
#
#  idx_on_backend_user_id_break_glassable_id_accessed__e06f302c56  (backend_user_id,break_glassable_id,accessed_at)
#  idx_on_break_glassable_id_break_glassable_type_14e1e3ce71       (break_glassable_id,break_glassable_type)
#  index_break_glass_records_on_backend_user_id                    (backend_user_id)
#  index_break_glass_records_on_break_glassable_id                 (break_glassable_id)
#
# Foreign Keys
#
#  fk_rails_...  (backend_user_id => backend_users.id)
#
class BreakGlassRecord < ApplicationRecord
  include PublicActivity::Model
  tracked owner: ->(controller, model) { controller&.user_for_public_activity }, recipient: proc { |controller, record| record.break_glassable.is_a?(Identity) ? record.break_glassable : record.break_glassable&.identity }, only: [ :create ]

  has_paper_trail

  belongs_to :backend_user, class_name: "Backend::User"
  belongs_to :break_glassable, polymorphic: true

  validates :reason, presence: true
  validates :accessed_at, presence: true

  scope :for_user_and_document, ->(user, document) { where(backend_user: user, break_glassable: document) }
  scope :recent, -> { where(accessed_at: 24.hours.ago..) }
end
