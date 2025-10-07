# == Schema Information
#
# Table name: identities
#
#  id                            :bigint           not null, primary key
#  aadhaar_number_bidx           :string
#  aadhaar_number_ciphertext     :text
#  birthday                      :date
#  came_in_through_adult_program :boolean          default(FALSE)
#  country                       :integer
#  deleted_at                    :datetime
#  first_name                    :string
#  hq_override                   :boolean          default(FALSE)
#  last_name                     :string
#  legal_first_name              :string
#  legal_last_name               :string
#  permabanned                   :boolean          default(FALSE)
#  phone_number                  :string
#  primary_email                 :string
#  ysws_eligible                 :boolean
#  created_at                    :datetime         not null
#  updated_at                    :datetime         not null
#  primary_address_id            :bigint
#  slack_id                      :string
#
# Indexes
#
#  index_identities_on_aadhaar_number_bidx  (aadhaar_number_bidx) UNIQUE
#  index_identities_on_deleted_at           (deleted_at)
#  index_identities_on_primary_address_id   (primary_address_id)
#  index_identities_on_slack_id             (slack_id)
#
# Foreign Keys
#
#  fk_rails_...  (primary_address_id => addresses.id)
#
class Identity < ApplicationRecord
  has_paper_trail
  acts_as_paranoid
  include PublicActivity::Model

  tracked owner: ->(controller, model) { controller&.user_for_public_activity }, only: [:create, :admin_update]

  include CountryEnumable

  include PublicIdentifiable
  set_public_id_prefix "ident"

  has_country_enum

  has_many :sessions, class_name: "IdentitySession", dependent: :destroy
  has_many :login_attempts
  has_many :login_codes, class_name: "Identity::LoginCode", dependent: :destroy
  has_many :v2_login_codes, class_name: "Identity::V2LoginCode", dependent: :destroy
  has_many :totps, class_name: "Identity::TOTP", dependent: :destroy
  has_many :backup_codes, class_name: "Identity::BackupCode", dependent: :destroy

  has_many :documents, class_name: "Identity::Document"
  has_many :verifications, class_name: "Verification"
  has_many :document_verifications, class_name: "Verification::DocumentVerification", dependent: :destroy
  has_many :aadhaar_verifications, class_name: "Verification::AadhaarVerification"
  has_many :vouch_verifications, class_name: "Verification::VouchVerification", dependent: :destroy
  has_many :addresses, class_name: "Address"
  belongs_to :primary_address, class_name: "Address", optional: true

  has_many :access_tokens, -> { where(revoked_at: nil) }, class_name: "Doorkeeper::AccessToken", foreign_key: :resource_owner_id
  has_many :programs, through: :access_tokens, source: :application

  has_many :resemblances, class_name: "Identity::Resemblance"
  has_many :break_glass_records, as: :break_glassable, dependent: :destroy

  has_many :all_access_tokens, class_name: "Doorkeeper::AccessToken", foreign_key: :resource_owner_id
  has_many :all_programs, through: :all_access_tokens, source: :application

  validates :first_name, :last_name, :country, :primary_email, :birthday, presence: true
  validates :primary_email, uniqueness: true
  validates :primary_email, 'valid_email_2/email': { mx: true, disposable: true }

  validates :slack_id, uniqueness: true, allow_blank: true
  validates :aadhaar_number, uniqueness: true, allow_blank: true
  validates :aadhaar_number, format: { with: /\A\d{12}\z/, message: "must be 12 digits" }, if: -> { aadhaar_number.present? }

  scope :search, ->(term) {
    return all if term.blank?

    sanitized_term = "%#{term}%"
    where(
      "first_name ILIKE ? OR last_name ILIKE ? OR primary_email ILIKE ? OR slack_id ILIKE ?",
      sanitized_term, sanitized_term, sanitized_term, sanitized_term
    )
  }

  scope :with_fatal_rejections, -> {
    joins(:verifications).where(verifications: { fatal: true, ignored_at: nil })
  }

  scope :verified_but_ysws_ineligible, -> {
    joins(:verifications).where(verifications: { status: "approved", ignored_at: nil }).where(ysws_eligible: false)
  }

  validate :birthday_must_be_at_least_six_years_ago

  has_encrypted :aadhaar_number
  blind_index :aadhaar_number

  validate :legal_names_must_be_complete

  before_validation :downcase_email
  before_commit :copy_legal_name_if_needed, on: :create

  def self.slack_authorize_url(redirect_uri)
    params = {
      client_id: ENV["SLACK_CLIENT_ID"],
      redirect_uri: redirect_uri,
      state: SecureRandom.hex(24),
      user_scope: "users.profile:read,users:read,users:read.email"
    }

    URI.parse("https://slack.com/oauth/v2/authorize?#{params.to_query}")
  end

  def self.link_slack_account(code, redirect_uri, current_identity)
    response = HTTP.post("https://slack.com/api/oauth.v2.access", form: {
      client_id: ENV["SLACK_CLIENT_ID"],
      client_secret: ENV["SLACK_CLIENT_SECRET"],
      code: code,
      redirect_uri: redirect_uri
    })

    data = JSON.parse(response.body.to_s)

    return { success: false, error: "Failed to exchange OAuth code" } unless data["ok"]

    # Get user info
    user_response = HTTP.auth("Bearer #{data["authed_user"]["access_token"]}")
                        .get("https://slack.com/api/users.info?user=#{data["authed_user"]["id"]}")

    user_data = JSON.parse(user_response.body.to_s)

    return { success: false, error: "Failed to get Slack user information" } unless user_data["ok"]

    slack_id = data.dig("authed_user", "id")

    existing_identity = find_by(slack_id: slack_id)
    if existing_identity && existing_identity != current_identity
      return { success: false, error: "This Slack account is already linked to another identity" }
    end

    current_identity.update!(slack_id: slack_id)

    { success: true, slack_id: slack_id }
  end

  def slack_linked? = slack_id.present?

  def onboarding_step
    return :basic_info unless persisted?

    unless verifications.where(status: %w[approved pending]).any?
      if country == "IN" && Flipper.enabled?(:authbridge_aadhaar_2025_07_10, self)
        return :aadhaar
      else
        return :document
      end
    end

    return :address unless primary_address_id.present?

    :submitted
  end

  def onboarding_complete? = onboarding_step == :submitted

  def needs_documents? = country != "IN" && onboarding_step == :document

  def needs_aadhaar? = country == "IN" && Flipper.enabled?(:authbridge_aadhaar_2025_07_10, self) && onboarding_step == :aadhaar

  def latest_verification = verifications.not_ignored.order(created_at: :desc).first

  # EWWWW
  def verification_status
    return "ineligible" if permabanned

    verfs = verifications.not_ignored
    return "needs_submission" if verfs.empty?

    verification_statuses = verfs.pluck(:status)

    return "verified" if verification_statuses.include?("approved")
    return "pending" if verification_statuses.include?("pending")

    rejected_verifications = verfs.where(status: "rejected")

    has_fatal_rejection = rejected_verifications.any?(&:fatal_rejection?)

    has_fatal_rejection ? "ineligible" : "needs_submission"
  end

  def verification_status_reason
    return nil unless latest_verification&.rejected?

    latest_verification.rejection_reason
  end

  def verification_status_reason_details
    return nil unless latest_verification&.rejected?

    latest_verification.rejection_reason_details
  end

  def needs_resubmission?
    # Only show rejection details and resubmission prompts if:
    # 1. There are rejected verifications with retryable reasons
    # 2. AND there are no pending verifications (user hasn't resubmitted yet)
    verifications.not_ignored.retryable_rejections.any? &&
      !verifications.not_ignored.pending.any?
  end

  def rejected_verifications_needing_resubmission
    return Verification.none unless needs_resubmission?

    verifications.not_ignored.retryable_rejections
  end

  def in_resubmission_flow?
    # Show resubmission context if there are rejected verifications with retryable reasons
    # This is used in the document form to show context about previous rejections
    verification_status == "pending" &&
      verifications.not_ignored.retryable_rejections.any?
  end

  def rejected_verifications_for_context
    verifications.not_ignored.retryable_rejections
  end

  # TODO: this is schnasty
  def onboarding_redirect_path
    return Rails.application.routes.url_helpers.basic_info_onboarding_path unless persisted?

    if country == "IN" && Flipper.enabled?(:authbridge_aadhaar_2025_07_10, self)
      return Rails.application.routes.url_helpers.aadhaar_onboarding_path if needs_aadhaar_upload?
      return Rails.application.routes.url_helpers.aadhaar_step_2_onboarding_path unless aadhaar_verifications.pending.any?
    else
      return Rails.application.routes.url_helpers.document_onboarding_path if needs_document_upload?
    end

    return Rails.application.routes.url_helpers.address_onboarding_path unless primary_address_id.present?

    Rails.application.routes.url_helpers.submitted_onboarding_path
  end

  def needs_document_upload?
    return false if country == "IN" && Flipper.enabled?(:authbridge_aadhaar_2025_07_10, self)
    return false if verification_status == "ineligible"
    return true unless verifications.not_ignored.where(status: %w[approved pending]).any?
    return false if verification_status == "verified"
    needs_resubmission?
  end

  def needs_aadhaar_upload?
    return false unless country == "IN"
    return false if verification_status == "ineligible"
    return true unless verifications.not_ignored.where(status: %w[approved pending draft]).any?
    return false if verification_status == "verified"
    needs_resubmission?
  end

  def under_13? = age <= 13

  def locked? = locked_at.present?

  def unlock! = update!(locked_at: nil)

  def lock!
    update!(locked_at: Time.now)
    sessions.destroy_all
  end

  def age = (Date.today - birthday).days.in_years

  def phone_number_verified? = phone_number.present?

  def totp = totps.verified.first

  def backup_codes_enabled? = backup_codes.active.any?

  def legacy_migrated? = legacy_migrated_at.present?

  def suggested_aadhaar_password
    name = "#{legal_first_name}#{legal_last_name}".presence || "#{first_name}#{last_name}"
    "#{name.gsub(" ", "")[...4].upcase}#{birthday.year}"
  end

  def to_saml_nameid(options = {})
    SAML2::NameID.new(
      "HCID_#{Rails.env.development? ? "DEV" : "PROD"}_#{hashid}",
      SAML2::NameID::Format::PERSISTENT,
      **options
    )
  end

  # spray & pray - SAML2 gem will only pull the attrs an SP asks for in its metadata
  def to_saml_attributes
    attrs = []

    attrs << SAML2::Attribute.new("User.Email", primary_email, "User Email", SAML2::Attribute::NameFormats::UNSPECIFIED)
    attrs << SAML2::Attribute.new("User.FirstName", first_name, "User First Name", SAML2::Attribute::NameFormats::UNSPECIFIED)
    attrs << SAML2::Attribute.new("User.LastName", last_name, "User Last Name", SAML2::Attribute::NameFormats::UNSPECIFIED)
    attrs << SAML2::Attribute.new("email", primary_email, "User Email", SAML2::Attribute::NameFormats::UNSPECIFIED)
    attrs << SAML2::Attribute.new("firstName", first_name, "User First Name", SAML2::Attribute::NameFormats::UNSPECIFIED)
    attrs << SAML2::Attribute.new("lastName", last_name, "User Last Name", SAML2::Attribute::NameFormats::UNSPECIFIED)
    attrs
  end

  alias_method :to_param, :public_id

  private

  def downcase_email
    self.primary_email = primary_email&.downcase
  end

  def copy_legal_name_if_needed
    self.legal_first_name = first_name if legal_first_name.blank?
    self.legal_last_name = last_name if legal_last_name.blank?
  end

  def legal_names_must_be_complete
    if legal_first_name.present? && legal_last_name.blank?
      errors.add(:legal_last_name, "must be present when legal first name is provided")
    elsif legal_last_name.present? && legal_first_name.blank?
      errors.add(:legal_first_name, "must be present when legal last name is provided")
    end
  end

  def birthday_must_be_at_least_six_years_ago
    return unless birthday.present?

    six_years_ago = Date.current - 6.years
    if birthday > six_years_ago
      errors.add(:base, "Are you sure about that birthday?")
    end
  end
end
