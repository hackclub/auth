# frozen_string_literal: true

class SAMLCertificatePolicy < ApplicationPolicy
  def index? = saml_officer?

  def show? = saml_officer?

  def create? = saml_officer?

  def promote? = saml_officer?

  def retire? = saml_officer?

  private

  def saml_officer? = user&.saml_officer?
end
