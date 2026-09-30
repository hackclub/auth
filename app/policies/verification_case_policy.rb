class VerificationCasePolicy < ApplicationPolicy
  def index? = user_is_manual_document_verifier?

  def show? = user_is_manual_document_verifier?

  def create? = user_is_manual_document_verifier?

  def resend_link? = user_is_manual_document_verifier?

  def hold_call? = user_is_manual_document_verifier?

  def comment? = user_is_manual_document_verifier?

  def decide? = user_is_manual_document_verifier?
end
