module SAMLService
  module Signing
    DS_NS = "http://www.w3.org/2000/09/xmldsig#"
    SAML_NS = "urn:oasis:names:tc:SAML:2.0:assertion"
    
    class << self
      def sign_response(response)
        unsigned_xml = response.to_xml.to_s
        doc = Nokogiri::XML(unsigned_xml) { |cfg| cfg.noblanks }
        
        assertion = doc.at_xpath('//saml:Assertion', 'saml' => SAML_NS)
        assertion_digest = calculate_digest(assertion)
        assertion_signature = build_complete_signature(assertion['ID'], assertion_digest)
        assertion_issuer = assertion.at_xpath('saml:Issuer', 'saml' => SAML_NS)
        assertion_issuer.add_next_sibling(assertion_signature)
        
        response_elem = doc.at_xpath('//samlp:Response', 'samlp' => 'urn:oasis:names:tc:SAML:2.0:protocol')
        response_digest = calculate_digest(response_elem)
        response_signature = build_complete_signature(response_elem['ID'], response_digest)
        response_issuer = response_elem.at_xpath('saml:Issuer', 'saml' => SAML_NS)
        response_issuer.add_next_sibling(response_signature)
        
        save_opts = Nokogiri::XML::Node::SaveOptions::AS_XML | Nokogiri::XML::Node::SaveOptions::NO_DECLARATION
        doc.to_xml(save_with: save_opts)
      end

      private

      def calculate_digest(node)
        canon_xml = node.canonicalize(Nokogiri::XML::XML_C14N_EXCLUSIVE_1_0, [])
        hash = OpenSSL::Digest::SHA256.digest(canon_xml)
        Base64.strict_encode64(hash).gsub(/\n/, '')
      end

      def build_complete_signature(reference_id, digest)
        signed_info = build_signed_info(reference_id, digest)
        signature_value = sign_data(signed_info)
        build_signature(signed_info, signature_value)
      end

      def build_signed_info(reference_id, digest)
        builder = Nokogiri::XML::Builder.new do |xml|
          xml['ds'].SignedInfo('xmlns:ds' => DS_NS) do
            xml['ds'].CanonicalizationMethod('Algorithm' => 'http://www.w3.org/2001/10/xml-exc-c14n#')
            xml['ds'].SignatureMethod('Algorithm' => 'http://www.w3.org/2001/04/xmldsig-more#rsa-sha256')
            xml['ds'].Reference('URI' => "##{reference_id}") do
              xml['ds'].Transforms do
                xml['ds'].Transform('Algorithm' => 'http://www.w3.org/2000/09/xmldsig#enveloped-signature')
                xml['ds'].Transform('Algorithm' => 'http://www.w3.org/2001/10/xml-exc-c14n#')
              end
              xml['ds'].DigestMethod('Algorithm' => 'http://www.w3.org/2001/04/xmlenc#sha256')
              xml['ds'].DigestValue(digest)
            end
          end
        end
        builder.doc.root
      end

      def sign_data(signed_info_node)
        canon = signed_info_node.canonicalize(Nokogiri::XML::XML_C14N_EXCLUSIVE_1_0)
        key = OpenSSL::PKey::RSA.new(Entities.private_key)
        signature = key.sign(OpenSSL::Digest::SHA256.new, canon)
        Base64.strict_encode64(signature).gsub(/\n/, '')
      end

      def build_signature(signed_info_node, signature_value)
        builder = Nokogiri::XML::Builder.new do |xml|
          xml['ds'].Signature('xmlns:ds' => DS_NS) do
            xml.parent << signed_info_node
            xml['ds'].SignatureValue(signature_value)
            xml['ds'].KeyInfo do
              xml['ds'].X509Data do
                xml['ds'].X509Certificate(Entities.x509_certificate.gsub(/-----(BEGIN|END) CERTIFICATE-----|\s/, ''))
              end
            end
          end
        end
        builder.doc.root
      end
    end
  end
end
