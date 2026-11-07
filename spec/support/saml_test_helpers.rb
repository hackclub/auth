# frozen_string_literal: true

# For specs that drive the SAML IdP end to end: a throwaway signing key, test SPs loaded
# through the real SAMLService::Entities loader, and a way to read back what got posted.
module SAMLTestHelpers
  HTTP_POST_BINDING = "urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST"

  # generating the key is the slow part, so the whole run shares one
  def self.idp_key = @idp_key ||= OpenSSL::PKey::RSA.new(2048)

  def self.idp_certificate
    @idp_certificate ||= OpenSSL::X509::Certificate.new.tap do |cert|
      cert.version = 2
      cert.serial = 1
      cert.subject = cert.issuer = OpenSSL::X509::Name.parse("/CN=hca-test-idp")
      cert.public_key = idp_key.public_key
      cert.not_before = Time.now - 3600
      cert.not_after = Time.now + 86_400
      cert.sign(idp_key, OpenSSL::Digest.new("SHA256"))
    end
  end

  # Serves +entries+ (service_providers entries, shaped like config/saml.yml's) in place of
  # the environment's SPs.
  def use_saml_service_providers(*entries)
    allow(SAMLService::Entities).to receive(:service_providers)
      .and_return(SAMLService::Entities.build_service_providers(entries))
  end

  # SAMLService::Signing reads the IdP key and certificate from the files ENV points at.
  def stub_saml_signing
    allow(SAMLService::Entities).to receive_messages(
      private_key: SAMLTestHelpers.idp_key.to_pem,
      x509_certificate: Base64.strict_encode64(SAMLTestHelpers.idp_certificate.to_der)
    )
  end

  def entitlement!(slug)
    Directory::Collection.create!(kind: "entitlement", slug:, name: slug)
  end

  def add_member!(collection, identity: nil, group: nil)
    Directory.mutate!(cause: "test") do
      if identity
        Directory::Membership.create!(collection:, member_person: Directory::Person.find_or_create_by!(identity:))
      else
        Directory::Membership.create!(collection:, member_group: group)
      end
    end
  end

  # The form the page auto-submits: where it posts, and the SAMLResponse it carries (parsed).
  def saml_post_target = Nokogiri::HTML(response.body).at_css("form")&.[]("action")

  def posted_saml_response
    field = Nokogiri::HTML(response.body).at_css("input[name=SAMLResponse]")
    field && Nokogiri::XML(Base64.decode64(field["value"]))
  end

  def posted_name_id
    posted_saml_response&.at_xpath("//saml:Assertion/saml:Subject/saml:NameID", "saml" => SAML2::Namespaces::SAML)&.text
  end
end
