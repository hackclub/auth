class VerificationCasePolicy < ApplicationPolicy
  def index? = user_is_manual_document_verifier?

  def show? = user_is_manual_document_verifier?

  def create? = user_is_manual_document_verifier?

  def resend_link? = user_is_manual_document_verifier?

  def hold_call? = user_is_manual_document_verifier?

  def escalate? = user_is_manual_document_verifier?

  def comment? = user_is_manual_document_verifier?

  def decide?
    return false unless user_is_manual_document_verifier?
    # escalated cases need a second pair of eyes — the person who
    # escalated can't also resolve
    return record.events.where(key: "escalated").where.not(actor: user).exists? || user.super_admin? if record.escalated?

    true
  end
end
