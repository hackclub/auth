class Identity::DocumentPolicy < ApplicationPolicy
  def index? = user_is_manual_document_verifier?

  def show? = user_is_manual_document_verifier?

  def verify? = user_is_manual_document_verifier?

  alias_method :approve?, :verify?
  alias_method :reject?, :verify?
end
