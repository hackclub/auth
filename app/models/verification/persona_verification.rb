# the shape of an inquiry before it meets a person.
#
# a template is a door — it has a name in credentials and a set of
# fields it will accept as gifts. each field is a small promise:
# "give me this about the person and i will not ask them twice."
#
# when it's time to open the door, the identity walks through
# and offers what it has. nils are left on the doorstep.
#
class Verification::PersonaVerification < Verification
  include Verification::Rejectable
  include HasPersonaUrl
  has_persona_url "inquiries", :persona_inquiry_id

  encrypts :persona_session_token

  validates :persona_inquiry_id, uniqueness: { allow_nil: true, conditions: -> { where(deleted_at: nil) } }
  validate :persona_record_matches_inquiry, if: -> { persona_record_id.present? && persona_inquiry_id.present? && (persona_record_id_changed? || persona_inquiry_id_changed?) }

  # -- templates ---------------------------------------------------------
  #
  # declare templates here, map fields to lambdas or symbols.
  # country routing picks the first match; :default has no countries
  # so it catches everything that falls through.
  #
  # the template_id comes from credentials:
  #   persona.templates.default  /  persona.template_id  (single-key fallback)
  #

  Template = Data.define(:name, :countries, :fields) do
    def matches?(identity)
      countries.empty? || countries.include?(identity.country)
    end

    def prefill_for(identity)
      fields.each_with_object({}) do |(field, source), filled|
        value = source.is_a?(Symbol) ? identity.public_send(source) : source.call(identity)
        filled[field] = value if value.present?
      end
    end
  end

  TEMPLATES = [
    Template.new(:default, [], {
      "name-first":    ->(i) { i.legal_first_name.presence || i.first_name },
      "name-last":     ->(i) { i.legal_last_name.presence || i.last_name },
      birthdate:       ->(i) { i.birthday&.iso8601 },
      "email-address": :primary_email,
      "phone-number":  :phone_number
    })
  ].freeze

  rejection_reasons(
    poor_quality:  { name: "Poor image quality",                  fatal: false },
    blurry:        { name: "Image too blurry to read",            fatal: false },
    expired:       { name: "Expired document",                    fatal: false },
    under_13:      { name: "Submitter is under 13 years old",     fatal: false },
    other:         { name: "Other fixable issue",                 fatal: false },
    too_many_attempts: { name: "Too many failed attempts",        fatal: false },
    inquiry_expired:   { name: "Verification session expired",    fatal: false },
    info_mismatch: { name: "Information doesn't match profile",   fatal: true },
    altered:       { name: "Document appears altered/fraudulent", fatal: true },
    duplicate:     { name: "This identity is a duplicate",        fatal: true },
    fraud:         { name: "Fraudulent submission",               fatal: true }
  )

  aasm column: :status, timestamps: true, whiny_transitions: true, whiny_persistence: true do
    state :draft, initial: true
    state :pending
    state :approved
    state :rejected

    event :mark_pending do
      transitions from: :draft, to: :pending
    end

    event :approve do
      transitions from: :pending, to: :approved

      after do
        set_ysws_eligibility!
      end
    end

    event :mark_as_rejected do
      transitions from: [ :draft, :pending ], to: :rejected
      before { |reason, details| set_rejection_fields(reason, details) }
      after  { notify_rejection }
    end
  end

  def default_rejection_reason
    doc_under_13 = persona_record&.birthdate && Identity.calculate_age(persona_record.birthdate) < 13
    if identity.under_13? || doc_under_13
      "under_13"
    elsif identity.resemblances.any?
      "duplicate"
    end
  end

  # polymorphic interface
  def document_type_label = "Government ID (Persona)"
  def review_info_partial = "backend/verifications/review_persona_info"
  def review_full_partial = "backend/verifications/review_persona_full"
  def relevant_record     = persona_record
  def needs_break_glass?         = true
  def auto_break_glass_reason    = pending? ? "to review submission" : nil
  def nukeable?                  = draft? || pending?
  def auto_approvable?                  = true
  def status_pending_partial     = "verifications/status/pending_persona"

  def inquiry_unlinked?
    return false unless persona_inquiry_id.present? && persona_record_id.present?
    persona_record&.inquiry_id != persona_inquiry_id
  end

  def relink!
    raise "no persona record linked" unless persona_record
    update_columns(persona_inquiry_id: persona_record.inquiry_id)
  end

  def generate_inquiry!
    raise "this verification already has an inquiry!" if persona_inquiry_id.present?

    inquiry = Persona.instance.create_inquiry(
      template_id: resolve_template_id,
      account_reference_id: identity.public_id,
      fields: resolve_template.prefill_for(identity)
    )

    update!(persona_inquiry_id: inquiry.id, persona_session_token: inquiry.session_token)
    link_persona_account!(inquiry.account_id)

    inquiry
  end

  def link_persona_account!(account_id)
    return if account_id.blank? || identity.persona_account_id.present?

    identity.update!(persona_account_id: account_id)
  rescue ActiveRecord::RecordInvalid => e
    raise unless e.message.include?("Persona account")

    Sentry.capture_message(
      "Persona account already linked to another identity",
      level: :warning,
      extra: {
        identity_public_id: identity.public_id,
        persona_account_id: account_id,
        existing_identity: Identity.find_by(persona_account_id: account_id)&.public_id
      }
    )
  end

  private

  def resolve_template
    TEMPLATES.find { |t| t.matches?(identity) } || TEMPLATES.first
  end

  def resolve_template_id
    creds = Rails.application.credentials.persona
    if creds.respond_to?(:templates) && creds.templates
      creds.templates[resolve_template.name]
    else
      creds.template_id
    end
  end

  def persona_record_matches_inquiry
    return unless persona_record&.inquiry_id
    return if persona_record.inquiry_id == persona_inquiry_id

    Sentry.capture_message(
      "PersonaRecord inquiry_id does not match verification persona_inquiry_id",
      level: :error,
      tags: { data_integrity: true, component: "persona" },
      extra: {
        verification_id: id,
        identity_id: identity_id,
        persona_inquiry_id: persona_inquiry_id,
        record_inquiry_id: persona_record.inquiry_id,
        persona_record_id: persona_record_id
      }
    )
    errors.add(:persona_record, "inquiry_id (#{persona_record.inquiry_id}) does not match persona_inquiry_id (#{persona_inquiry_id})")
  end

  def set_ysws_eligibility!
    return unless persona_record&.birthdate
    age = Identity.calculate_age(persona_record.birthdate)
    eligible = age.between?(13, 17)
    identity.update!(ysws_eligible: eligible)
    create_activity(:ysws_eligibility_set, recipient: identity,
      parameters: { eligible: eligible, age: age })
  end
end
