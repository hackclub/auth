# frozen_string_literal: true

class TombstonedEmail < ApplicationRecord
  validates :email_digest, presence: true, uniqueness: true

  def self.digest(email)
    normalized = email.to_s.strip.downcase
    OpenSSL::HMAC.hexdigest("SHA256", pepper, normalized)
  end

  def self.tombstoned?(email)
    exists?(email_digest: digest(email))
  end

  def self.tombstone!(email)
    create!(email_digest: digest(email))
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    # already tombstoned
  end

  def self.pepper
    Rails.application.secret_key_base
  end
end
