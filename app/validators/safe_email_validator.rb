# frozen_string_literal: true

# Validates that an email address is both RFC-valid and safe for downstream
# consumption (CSV export, LDAP, mail headers, etc.). Rejects local-part
# characters that are technically RFC 5321-legal but never appear in real
# human email addresses and are common injection vectors (=, ', !, |, etc.).
#
# Usage:
#   validates :email, safe_email: true
#   validates :email, safe_email: { disposable: false, mx: false }
#
# Options:
#   disposable: true  — reject known disposable/temporary domains (default: false)
#   mx: true          — reject domains without MX records (default: false)
#   message:          — override the default `:invalid` error key
#
class SafeEmailValidator < ActiveModel::EachValidator
  LOCAL_PART_PATTERN = /\A[a-z0-9._+-]+\z/

  def validate_each(record, attribute, value)
    return if value.blank?

    email = value.to_s.strip.downcase
    address = ValidEmail2::Address.new(email)

    unless address.valid?
      record.errors.add(attribute, error_type, **error_options)
      return
    end

    local_part = email.split("@", 2).first
    unless local_part.match?(LOCAL_PART_PATTERN)
      record.errors.add(attribute, error_type, **error_options)
      return
    end

    if options[:disposable] && address.disposable?
      record.errors.add(attribute, :temporary, **error_options)
      return
    end

    if options[:mx] && !address.valid_mx?
      record.errors.add(attribute, :no_mx_record, **error_options)
    end
  end

  private

  def error_type
    options.fetch(:message, :invalid)
  end

  def error_options
    options.except(:disposable, :mx, :message)
  end
end
