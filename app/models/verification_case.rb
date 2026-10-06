# a manual verification call case — the container for the whole
# journey from "persona failed me, help" to a human decision.
#
# the case is workflow state; the durable outcome lives on a
# Verification::ManualVerificationCall created at decision time.
class VerificationCase < ApplicationRecord
  acts_as_paranoid

  include AASM
  include PublicActivity::Model

  has_paper_trail

  include PublicIdentifiable
  set_public_id_prefix "vcase"

  FLIPPER_FLAG = :manual_verification_call_2026_07_03
  ACCESS_TOKEN_TTL = 7.days

  belongs_to :identity
  belongs_to :opened_by, class_name: "Backend::User", optional: true
  belongs_to :verification, optional: true
  # soft-deleting a case (acts_as_paranoid still runs the destroy callbacks)
  # must not touch what hangs off it, so nothing here cascades:
  #   - events are append-only; destroying one raises
  #     ActiveRecord::ReadOnlyRecord, which would abort the whole destroy
  #   - comments are the reviewers' record of the decision
  #   - documents are paranoid, but destroying one hard-deletes its
  #     ActiveStorage attachment (purging the evidence file) and its
  #     break-glass records — not something a soft delete should do
  # the children stay put and remain reachable through the soft-deleted
  # case; the privacy path that actually purges is DeletionService.
  # a case is never hard-deleted — see #destroy_fully! below.
  has_many :documents, class_name: "VerificationCase::Document", dependent: nil
  has_many :events, class_name: "VerificationCase::Event", dependent: nil
  has_many :comments, class_name: "VerificationCase::Comment", dependent: nil

  encrypts :persona_session_token

  # which kind of document backs this case — a government document (persona
  # rejected it but a human can read it) or alternative documents (transcript,
  # report card, school letter). NOT the org-wide verification tiers.
  enum :document_class, { government_id: "government_id", alternative: "alternative" }

  ALTERNATIVE_REASONS = {
    "no_government_id" => "I don't have any government-issued ID",
    "id_inaccessible" => "My ID exists but I can't access it right now",
    "guardian_refusal" => "My parent/guardian holds my documents",
    "other" => "Other (please explain)"
  }.freeze

  # what the user asserts about their document before any path (persona
  # capture or direct upload) may move the case to docs_submitted. the
  # reviewer's "name/DOB consistent" checklist compares against these.
  REQUIRED_SUBMITTED_FIELDS = %w[legal_name date_of_birth document_type issuing_authority].freeze

  validates :alternative_reason, inclusion: { in: ALTERNATIVE_REASONS.keys }, if: :alternative?
  validates :alternative_reason_details, presence: true, if: -> { alternative? && alternative_reason == "other" }
  validates :persona_inquiry_id, uniqueness: { allow_nil: true, conditions: -> { where(deleted_at: nil) } }

  CLOSED_STATUSES = %w[approved denied withdrawn].freeze

  scope :open_cases, -> { where.not(status: CLOSED_STATUSES) }
  scope :closed_cases, -> { where(status: CLOSED_STATUSES) }

  # invitation went out, user never opened it, link still good, not yet nudged.
  # the reminder_sent audit event is the "already sent" marker.
  #
  # "never opened" means the token is unconsumed (access_token_used_at nil).
  # a user who opened the link and then stalled mid-capture is still
  # link_sent, but their authenticated session is live — the reminder
  # rotates the link, which would reset used_at and lock that session out
  # (403 + a spurious link_rejected event). they get no nudge from this job;
  # nothing in the flow asks for a non-rotating one yet.
  scope :due_for_link_reminder, ->(quiet_for:) {
    where(status: "link_sent")
      .where(link_sent_at: ..quiet_for.ago)
      .where(access_token_used_at: nil)
      .where(access_token_expires_at: Time.current..)
      .where.not(id: VerificationCase::Event.where(key: "reminder_sent").select(:verification_case_id))
  }

  alias_method :to_param, :public_id

  aasm column: :status, timestamps: true, whiny_transitions: true, whiny_persistence: true do
    state :requested, initial: true
    state :link_sent
    state :docs_submitted
    state :call_scheduled
    state :call_held
    state :approved
    state :denied
    # closed by staff without a decision — opened by mistake, user went
    # quiet, user asked us to stop. no verification record is created.
    state :withdrawn

    event :send_link do
      transitions from: [ :requested, :link_sent ], to: :link_sent
    end

    # refused (AASM::InvalidTransition) unless attestation, biometric consent
    # and the submitted fields are already on the case — whichever path
    # (persona capture job or direct upload) is calling.
    event :submit_docs do
      transitions from: [ :link_sent, :docs_submitted ], to: :docs_submitted, guard: :docs_submission_prerequisites_met?
    end

    # reviewer wants the documents redone — back behind the booking gate.
    # only before a call is booked; once it's booked, talk about it on the call.
    event :request_redo do
      transitions from: :docs_submitted, to: :link_sent
      after { reset_capture! }
    end

    event :schedule_call do
      transitions from: [ :docs_submitted, :call_scheduled ], to: :call_scheduled
    end

    # booking cancelled without a rebook — back to "book your call"
    event :unschedule_call do
      transitions from: :call_scheduled, to: :docs_submitted
    end

    event :hold_call do
      transitions from: :call_scheduled, to: :call_held
    end

    event :approve do
      transitions from: :call_held, to: :approved
      after { close_out! }
    end

    event :deny do
      transitions from: :call_held, to: :denied
      after { close_out! }
    end

    event :withdraw do
      transitions from: [ :requested, :link_sent, :docs_submitted, :call_scheduled, :call_held ], to: :withdrawn
      after do
        close_out!
        invalidate_access_token!
      end
    end
  end

  def open? = !closed?
  def closed? = CLOSED_STATUSES.include?(status)

  # cases are soft-deleted only. the events under a case can't be deleted
  # (append-only) and the FK from events to cases means the row can't go
  # either; the privacy path is DeletionService, which scrubs the case and
  # its audit rows in place rather than removing them.
  def destroy_fully!
    raise ActiveRecord::ReadOnlyRecord, "verification cases are never hard-deleted; use DeletionService to scrub"
  end
  def decided? = approved? || denied?

  # -- feature flag ------------------------------------------------------

  def enable_flag! = Flipper.enable(FLIPPER_FLAG, identity)
  def revoke_flag! = Flipper.disable(FLIPPER_FLAG, identity)

  # -- single-use access link (mirrors Identity::V2LoginCode) -------------

  # once the link has been opened, the authenticated session is what gets
  # the user in (see ManualVerificationsController#require_case_access) —
  # so a fresh token does NOT re-arm the gate by default. clearing used_at
  # on a plain resend would 403 a user who is mid-flow in another tab, and
  # buys nothing: the email-holder proof was already established. only a
  # redo (reopen_gate: true) deliberately makes the user come back through
  # the new link.
  def generate_access_token!(reopen_gate: false)
    attrs = {
      access_token: SecureRandom.urlsafe_base64(32),
      access_token_expires_at: ACCESS_TOKEN_TTL.from_now
    }
    attrs[:access_token_used_at] = nil if reopen_gate
    update!(attrs)
    access_token
  end

  # rotate the token and (re)enter link_sent — the caller picks which
  # email carries the returned token (invitation, reminder, redo ...).
  #
  # runs under the row lock so the state is re-read first, and the
  # transition is checked BEFORE the token is touched: a case that has
  # moved on (stale "resend" tab, racing reviewer) raises
  # AASM::InvalidTransition with the token untouched, and a failed token
  # write rolls the transition back with it.
  def rotate_access_link!(reopen_gate: false)
    with_lock do
      send_link!
      generate_access_token!(reopen_gate: reopen_gate)
    end
  end

  # the emailed link stops working — a withdrawn case must not be enterable
  def invalidate_access_token!
    update!(access_token: nil, access_token_expires_at: nil)
  end

  # atomic single-use consume — the update_all guarded on used_at: nil
  # means two racing requests can't both win.
  def consume_access_token!(token)
    return false if token.blank? || access_token.blank?
    return false unless ActiveSupport::SecurityUtils.secure_compare(token, access_token)
    return false if access_token_expires_at.nil? || access_token_expires_at.past?

    self.class.where(id: id, access_token_used_at: nil)
      .update_all(access_token_used_at: Time.current) == 1
  end

  # -- persona capture-only inquiry ---------------------------------------

  # staff can open a case that avoids persona entirely (the "i don't want
  # to use persona" crowd) — those cases go straight to camera upload
  def persona_capture_available? = !skip_persona? && capture_template_id.present?

  # the reviewer can only tick "document matches selfie" if there is a
  # selfie: either inside the persona capture or taken live on our page
  def selfie_available? = persona_inquiry_id.present? || documents.where(document_kind: "selfie").exists?

  def generate_capture_inquiry!
    raise "this case already has an inquiry!" if persona_inquiry_id.present?

    return nil unless persona_capture_available? # skip-persona case or no template — camera upload instead

    inquiry = Persona.instance.create_inquiry(
      template_id: capture_template_id,
      account_reference_id: identity.public_id,
      # the capture template's field keys are underscored (name_first), unlike
      # the kyc templates' hyphenated ones. persona 400s on an unknown key.
      fields: {
        name_first: identity.legal_first_name.presence || identity.first_name,
        name_last: identity.legal_last_name.presence || identity.last_name,
        email_address: identity.primary_email
      }.compact
    )

    update!(persona_inquiry_id: inquiry.id, persona_session_token: inquiry.session_token)
    inquiry
  end

  # one capture-only template serves both document classes — the template
  # accepts arbitrary documents, and the selfie/liveness step applies either way
  def capture_template_id
    return nil if document_class.blank?

    creds = Rails.application.credentials.persona
    template = creds.respond_to?(:manual_capture_template) ? creds.manual_capture_template : nil
    template.presence || ENV["PERSONA_MANUAL_CAPTURE_TEMPLATE"].presence
  end

  # -- submission prerequisites ---------------------------------------------

  # names of anything still missing before submit_docs may run: the two
  # checkboxes plus each required submitted field
  def missing_submission_prerequisites
    missing = []
    missing << "attested" unless attested?
    missing << "biometric_consent" unless biometric_consent?
    REQUIRED_SUBMITTED_FIELDS.each { |field| missing << field if (submitted_fields || {})[field].blank? }
    missing
  end

  def docs_submission_prerequisites_met? = missing_submission_prerequisites.empty?

  # -- booking gate --------------------------------------------------------

  # cal.com link only revealed once docs are in
  def booking_available? = docs_submitted?

  def booking_url
    base = ENV["CALCOM_MANUAL_VERIFICATION_BOOKING_URL"]
    return nil if base.blank?

    uri = URI.parse(base)
    params = URI.decode_www_form(uri.query || "")
    params << [ "metadata[casePublicId]", public_id ]
    params << [ "email", identity.primary_email ]
    uri.query = URI.encode_www_form(params)
    uri.to_s
  end

  # -- audit log -------------------------------------------------------------

  def log_event!(key, actor: nil, data: {}, request: nil)
    events.create!(
      key: key.to_s,
      actor: actor,
      data: data,
      ip_address: request&.remote_ip,
      user_agent: request&.user_agent
    )
  end

  # a redo means a fresh capture: the finished persona inquiry can't be
  # re-run, so forget it and let start_capture create a new one. the old
  # inquiry id stays in the audit trail (capture_inquiry_created / redo_requested).
  # also used when a finished capture is refused for missing prerequisites.
  def reset_capture!
    update!(persona_inquiry_id: nil, persona_session_token: nil)
  end

  private

  # decision time: drop the flag. documents are retained (break-glass
  # gated) — the ManualVerificationCall itself is created by the decision flow.
  def close_out! = revoke_flag!
end
