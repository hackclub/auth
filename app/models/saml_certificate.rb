# frozen_string_literal: true

class SAMLCertificate < ApplicationRecord
  include AASM
  include PublicActivity::Model
  has_paper_trail

  KEY_DIR = ENV.fetch("SAML_KEY_DIR", "/data/certs")
  DEFAULT_CN = "auth.hackclub.com"
  # everything but CN, which the generate form can override
  SUBJECT = [ [ "C", "US" ], [ "ST", "Vermont" ], [ "L", "Burlington" ], [ "O", "Hack Club" ], [ "OU", "Identity Services" ] ].freeze
  VALIDITY_YEARS = 1..10
  ROTATION_LOCK = 0x5A4D4C # "SML", any constant bigint works for pg_advisory_xact_lock

  # rollover → signing (promote), old signing → rollover (so promoting it again is a rollback),
  # rollover → retired (retire, once every SP has the new cert)
  aasm column: :role, timestamps: true, whiny_persistence: true do
    state :rollover, initial: true
    state :signing
    state :retired

    event :promote do
      transitions from: :rollover, to: :signing
    end

    event :retire do
      transitions from: :rollover, to: :retired
    end
  end

  # every role change takes the rotation lock and re-reads the row first, so a stale tab
  # can't retire a cert someone else just promoted
  module RotationLocked
    def promote! = self.class.with_rotation_lock { reload; super() }
    def retire! = self.class.with_rotation_lock { reload; super() }
  end
  prepend RotationLocked

  validates :certificate, :key_path, :fingerprint, :expires_at, presence: true
  validates :fingerprint, uniqueness: true
  validate :key_usable, on: :create
  validate :key_usable, if: :becoming_signing?, on: :update
  # update only: import_from_env! has to accept whatever is signing today, even if it's expired
  validate :unexpired, if: :becoming_signing?, on: :update

  # runs inside the same transaction as the promotion, after validations pass,
  # so a failed promote never leaves zero signing certs
  before_save :demote_current_signing, if: :becoming_signing?

  before_validation :compute_fingerprint, if: -> { certificate.present? && fingerprint.blank? }
  before_validation :compute_expires_at, if: -> { certificate.present? && expires_at.blank? }

  class << self
    def current_signing = tolerating_missing_table { signing.first }

    def current_rollover = tolerating_missing_table { rollover.order(:id).first }

    # Entities compares this per request, so every puma worker notices a rotation
    def version = tolerating_missing_table { maximum(:updated_at) }

    def with_rotation_lock(&)
      transaction do
        connection.execute("SELECT pg_advisory_xact_lock(#{ROTATION_LOCK})")
        yield
      end
    end

    # Import the current env var cert into the DB as signing, so generate! creates a rollover.
    # The key is copied into KEY_DIR so the row never depends on files ops might swap out.
    def import_from_env!
      cert_path = ENV["SAML_IDP_CERT_PATH"]
      key_path = ENV["SAML_IDP_KEY_PATH"]
      raise "SAML_IDP_CERT_PATH not set" unless cert_path.present?
      raise "SAML_IDP_KEY_PATH not set" unless key_path.present?

      with_rotation_lock do
        raise "A signing certificate already exists in the database" if current_signing.present?

        create_with_key!(
          OpenSSL::PKey::RSA.new(File.read(key_path)),
          OpenSSL::X509::Certificate.new(File.read(cert_path)),
          role: "signing"
        )
      end
    end

    # Generate a new certificate + private key pair, write key to KEY_DIR, create DB record.
    # Auto-imports the env var cert first if no DB signing cert exists.
    def generate!(cn: DEFAULT_CN, validity_years: 1)
      unless VALIDITY_YEARS.cover?(validity_years)
        raise ArgumentError, "validity must be #{VALIDITY_YEARS.min}–#{VALIDITY_YEARS.max} years"
      end

      # keygen is slow, keep it outside the lock
      key, cert = build_keypair(cn, validity_years)

      with_rotation_lock do
        raise "A rollover certificate already exists. Promote or retire it first." if current_rollover.present?

        # If running on env vars with no DB cert, import the existing cert first
        # so the new one becomes rollover instead of immediately replacing it.
        import_from_env! if current_signing.blank? && ENV["SAML_IDP_CERT_PATH"].present?

        create_with_key!(key, cert, role: current_signing.present? ? "rollover" : "signing")
      end
    end

    private

    # only the pre-migration case (Entities loading before the table exists) means "no DB cert";
    # anything else (timeouts, failover) has to raise, or Entities silently falls back to env keys
    def tolerating_missing_table
      yield
    rescue ActiveRecord::StatementInvalid => e
      raise unless e.cause.is_a?(PG::UndefinedTable)
      nil
    end

    def build_keypair(cn, validity_years)
      key = OpenSSL::PKey::RSA.new(4096)
      cert = OpenSSL::X509::Certificate.new
      cert.version = 2
      cert.serial = SecureRandom.random_number(2**128)
      cert.subject = OpenSSL::X509::Name.new([ *SUBJECT, [ "CN", cn ] ])
      cert.issuer = cert.subject
      cert.public_key = key.public_key
      cert.not_before = Time.now.utc
      cert.not_after = cert.not_before + validity_years.years

      ef = OpenSSL::X509::ExtensionFactory.new
      ef.subject_certificate = cert
      ef.issuer_certificate = cert
      cert.add_extension(ef.create_extension("basicConstraints", "CA:FALSE", true))
      cert.add_extension(ef.create_extension("keyUsage", "digitalSignature", true))
      cert.sign(key, OpenSSL::Digest::SHA256.new)

      [ key, cert ]
    end

    def create_with_key!(key, cert, role:)
      key_path = write_key(key, cert)
      create!(
        role:,
        certificate: cert.to_pem,
        key_path:,
        signing_at: role == "signing" ? Time.current : nil
      )
    rescue
      File.delete(key_path) if key_path
      raise
    end

    # named by fingerprint so two certs can never share a file; O_EXCL refuses existing
    # files and symlinks, and the mode is set at creation so it's never world-readable
    def write_key(key, cert)
      path = File.join(KEY_DIR, "saml-#{OpenSSL::Digest::SHA256.hexdigest(cert.to_der).first(16)}.key")
      File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |f| f.write(key.to_pem) }
      path
    end
  end

  def x509 = @x509 ||= OpenSSL::X509::Certificate.new(certificate)

  def private_key = OpenSSL::PKey::RSA.new(File.read(key_path))

  def x509_certificate_base64 = Base64.strict_encode64(x509.to_der)

  def expired? = expires_at < Time.current

  def expires_soon? = !expired? && expires_at < 90.days.from_now

  def status
    return "expired" if expired?
    return "expiring" if expires_soon?
    "valid"
  end

  def days_until_expiry
    return 0 if expired?
    (expires_at.to_date - Date.current).to_i
  end

  private

  def becoming_signing? = will_save_change_to_role?(to: "signing")

  # a per-record update (not update_all) so paper_trail sees the demotion and updated_at moves
  def demote_current_signing
    SAMLCertificate.signing.where.not(id: id).find_each { |cert| cert.update!(role: "rollover") }
  end

  def compute_fingerprint
    self.fingerprint = OpenSSL::Digest::SHA256.hexdigest(x509.to_der)
      .scan(/../).join(":").upcase
  end

  def compute_expires_at = self.expires_at = x509.not_after

  # checked on create and again on every promote, since the key lives on this host's disk
  # and a redeploy or another replica may not have it
  def key_usable
    return if certificate.blank? || key_path.blank?

    errors.add(:key_path, "private key does not match certificate") unless x509.check_private_key(private_key)
  rescue SystemCallError => e
    errors.add(:key_path, "is not readable on this host (#{e.class.name.demodulize})")
  rescue OpenSSL::PKey::PKeyError, OpenSSL::X509::CertificateError => e
    errors.add(:key_path, "invalid key or certificate: #{e.message}")
  end

  def unexpired
    errors.add(:expires_at, "is in the past") if expires_at.present? && expires_at <= Time.current
  end
end
