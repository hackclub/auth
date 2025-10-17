# == Schema Information
#
# Table name: oauth_access_tokens
#
#  id                     :bigint           not null, primary key
#  expires_in             :integer
#  previous_refresh_token :string           default(""), not null
#  refresh_token          :string
#  resource_owner_type    :string
#  revoked_at             :datetime
#  scopes                 :string
#  token_bidx             :string
#  token_ciphertext       :text
#  created_at             :datetime         not null
#  application_id         :bigint           not null
#  resource_owner_id      :bigint
#
# Indexes
#
#  index_oauth_access_tokens_on_application_id     (application_id)
#  index_oauth_access_tokens_on_refresh_token      (refresh_token) UNIQUE
#  index_oauth_access_tokens_on_resource_owner_id  (resource_owner_id)
#  index_oauth_access_tokens_on_token_bidx         (token_bidx) UNIQUE
#  polymorphic_owner_oauth_access_tokens           (resource_owner_id,resource_owner_type)
#
# Foreign Keys
#
#  fk_rails_...  (application_id => oauth_applications.id)
#  fk_rails_...  (resource_owner_id => identities.id)
#
class OAuthToken < ApplicationRecord
  include ::Doorkeeper::Orm::ActiveRecord::Mixins::AccessToken
  include PublicActivity::Model
  tracked owner: ->(controller, model) { controller&.user_for_public_activity }, recipient: proc { |controller, record| record.resource_owner }, only: [ :create, :revoke ]

  PREFIX = "idntk."
  SIZE = 32

  scope :not_expired, -> { where(expires_in: nil).or(where("(oauth_access_tokens.created_at + make_interval(secs => expires_in)) >= ?", Time.now)) }
  scope :not_revoked, -> { where(revoked_at: nil).or(where(revoked_at: Time.now..)) }

  scope :accessible, -> { not_expired.and(not_revoked) }

  has_encrypted :token
  blind_index :token

  has_paper_trail skip: [ :token ]

  belongs_to :resource_owner, class_name: "Identity"

  def generate_token
    self.token = self.class.generate
  end

  def active?
    !revoked_at? && (expires_in.nil? || expires_in > 0)
  end

  def self.generate(options = {})
    token_size = options.delete(:size) || SIZE
    PREFIX + SecureRandom.urlsafe_base64(token_size)
  end
end
