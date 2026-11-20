# frozen_string_literal: true

class AddUniqueSigningIndexToSAMLCertificates < ActiveRecord::Migration[8.0]
  def change
    # at most one signing cert, enforced by the DB not just the rotation lock
    add_index :saml_certificates, :role, unique: true, where: "role = 'signing'", name: "index_saml_certificates_one_signing"
  end
end
