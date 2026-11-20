# links an inquiry that staff created by hand in the persona dashboard to
# the identity named in its reference id.
#
# this is the account recovery path: the user can't sign in or read their
# email, so staff make an inquiry with reference id = the identity's public
# id and send them persona's hosted link directly. persona's inquiry.created
# webhook carries the dashboard user's email as `creator` — only active
# reviewers count. once linked, the inquiry is an ordinary PersonaVerification
# and the usual completed/approved webhooks drive it, except it never
# auto-approves (see PersonaVerification::STAFF_CREATED_ISSUE).
class Persona::LinkStaffInquiryJob < ApplicationJob
  queue_as :default

  PERSONA_TYPES = %w[Verification::PersonaVerification Verification::PersonaStudentIdVerification].freeze

  def perform(inquiry_id:, creator:, reference_id:)
    return if Verification.exists?(persona_inquiry_id: inquiry_id)
    return if VerificationCase.exists?(persona_inquiry_id: inquiry_id)

    Sentry.set_tags(component: "persona", event: "inquiry.created")
    Sentry.set_extras(inquiry_id: inquiry_id, reference_id: reference_id)

    staff = staff_user_for(creator)
    unless staff
      Sentry.capture_message("[Persona] dashboard inquiry created by someone who isn't an active reviewer", level: :warning)
      return
    end

    identity = Identity.find_by_public_id(reference_id)
    unless identity
      Sentry.capture_message("[Persona] dashboard inquiry reference id doesn't match an identity", level: :warning)
      return
    end

    stale_inquiry_ids = []
    verification = identity.with_lock do
      # something already under review — don't stack a second submission on it
      if identity.verifications.where(type: PERSONA_TYPES, status: :pending).exists?
        Sentry.capture_message("[Persona] dashboard inquiry for an identity with a pending verification", level: :warning)
        nil
      else
        # a draft would shadow this one when the user next signs in, and its
        # inquiry is stale anyway — same cleanup the verification flow does
        identity.verifications.where(type: PERSONA_TYPES, status: :draft).find_each do |draft|
          stale_inquiry_ids << draft.persona_inquiry_id if draft.persona_inquiry_id.present?
          draft.destroy!
        end

        Verification::PersonaVerification.create!(
          identity: identity,
          persona_inquiry_id: inquiry_id,
          issues: [ Verification::PersonaVerification::STAFF_CREATED_ISSUE ]
        )
      end
    end
    return unless verification

    stale_inquiry_ids.each do |stale_id|
      Persona.instance.expire_inquiry(stale_id)
    rescue Persona::APIError => e
      Sentry.capture_exception(e)
    end

    verification.create_activity(:persona_inquiry_linked_by_staff, owner: staff, recipient: identity,
      parameters: { inquiry_id: inquiry_id, expired_inquiry_ids: stale_inquiry_ids })
  end

  private

  def staff_user_for(creator)
    Backend::User.joins(:identity)
      .where(active: true)
      .where("lower(identities.primary_email) = ?", creator.to_s.strip.downcase)
      .where("backend_users.super_admin OR backend_users.manual_document_verifier")
      .first
  end
end
