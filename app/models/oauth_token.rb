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
  tracked owner: proc { |controller, record| record.resource_owner }, recipient: proc { |controller, record| record.resource_owner }, only: [ :create, :revoke ]

  ACCESS_TOKEN_PREFIX = "idntk."
  REFRESH_TOKEN_PREFIX = "idnrf."
  SIZE = 32

  scope :not_expired, -> { where(expires_in: nil).or(where("(oauth_access_tokens.created_at + make_interval(secs => expires_in)) >= ?", Time.now)) }
  scope :not_revoked, -> { where(revoked_at: nil).or(where(revoked_at: Time.now..)) }

  scope :accessible, -> { not_expired.and(not_revoked) }

  has_encrypted :token
  blind_index :token

  has_paper_trail skip: [ :token ]

  belongs_to :resource_owner, class_name: "Identity"

  def generate_token
    @raw_token = self.class.generate_access_token
    secret_strategy.store_secret(self, :token, @raw_token)
  end

  def generate_refresh_token
    @raw_refresh_token = self.class.generate_refresh_token
    Doorkeeper.config.token_secret_strategy.store_secret(self, :refresh_token, @raw_refresh_token)
  end

  def active?
    !revoked_at? && (expires_in.nil? || expires_in > 0)
  end

  def self.generate_access_token(size: SIZE)
    ACCESS_TOKEN_PREFIX + SecureRandom.urlsafe_base64(size)
  end

  def self.generate_refresh_token(size: SIZE)
    REFRESH_TOKEN_PREFIX + SecureRandom.urlsafe_base64(size)
  end
end
