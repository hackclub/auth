# frozen_string_literal: true

class Deletion < ApplicationRecord
  validates :email_hash, presence: true, uniqueness: true

  def self.hmac(value)
    OpenSSL::HMAC.hexdigest("SHA256", pepper, value.to_s)
  end

  def self.hash_email(email)
    hmac(email.to_s.strip.downcase)
  end

  def self.hash_ip(ip)
    hmac(ip.to_s.strip)
  end

  def self.tokenize_name(name)
    normalized = name.to_s.strip.downcase
    normalized = ActiveSupport::Inflector.transliterate(normalized)
    normalized = normalized.gsub(/[-']/, " ")
    normalized = normalized.gsub(/\s+/, " ").strip
    normalized.split(" ")
  end

  def self.name_combo_hashes(name, dob)
    tokens = tokenize_name(name).uniq
    generate_combo_hashes(tokens, dob)
  end

  def self.name_combo_hashes_for_identity(identity)
    tokens = []
    tokens.concat(tokenize_name("#{identity.first_name} #{identity.last_name}"))
    if identity.legal_first_name.present? || identity.legal_last_name.present?
      tokens.concat(tokenize_name("#{identity.legal_first_name} #{identity.legal_last_name}"))
    end
    tokens.uniq!

    generate_combo_hashes(tokens, identity.birthday)
  end

  def self.generate_combo_hashes(tokens, dob)
    tokens = tokens.reject(&:blank?)
    dob_str = dob.to_s

    if tokens.size <= 1
      return tokens.map { |t| hmac("#{t}|#{dob_str}") }
    end

    tokens.combination(2).map do |pair|
      sorted = pair.sort
      hmac("#{sorted[0]}|#{sorted[1]}|#{dob_str}")
    end
  end

  def self.email_tombstoned?(email)
    exists?(email_hash: hash_email(email))
  end

  def self.pepper
    Rails.application.secret_key_base
  end
end
