class VerificationPolicy < ApplicationPolicy
  def index? = user_is_manual_document_verifier?

  def pending? = user_is_manual_document_verifier?

  def show? = user_is_manual_document_verifier?

  def approve? = user_is_manual_document_verifier?

  def reject? = user_is_manual_document_verifier?

  def ignore? = user&.super_admin?
end
