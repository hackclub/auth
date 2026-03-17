module SAMLService
    module Entities
        class << self
        # returns a SAML2::IdentityProvider object
        def idp
            @idp ||= begin
                idp = SAML2::IdentityProvider.new

                # contacts:
                idp.contacts = idp_meta.dig(:contacts).map { |details| yaml_to_saml(details, SAML2::Contact.new) }

                # organization metadata:
                idp.organization = SAML2::Organization.new(
                    idp_meta.dig(:organization, :name),
                    idp_meta.dig(:organization, :display_name),
                    idp_meta.dig(:organization, :url)
                )

                idp.want_authn_requests_signed = false
                idp.instance_variable_set(:@name_id_formats, [ SAML2::NameID::Format::UNSPECIFIED ])

                # single sign-on services:
                idp_meta.dig(:single_sign_on_services)&.each do |sso_config|
                    endpoint = SAML2::Endpoint.new(sso_config[:location], sso_config[:binding])
                    idp.single_sign_on_services << endpoint
                end

                idp.keys << signing_key if signing_key.present?

                idp
            end
        end

        def idp_entity = @idp_entity ||= begin
            ent = SAML2::Entity.new
            ent.entity_id = idp_meta.dig(:entity_id)
            ent.instance_variable_set(:@roles, [ idp ])
            ent
        end

        def metadata_xml
          @metadata_xml ||= begin
                              xml = idp_entity.to_xml
                              xml.root.add_child Nokogiri::XML::Comment.new(xml, " haiii :3 ")
                              xml.add_child Nokogiri::XML::Comment.new(xml, " curious thing, aren't you? – https://hack.af/gh/auth , glory awaits")
                              xml.to_s
                            end
        end
        def service_providers
            @service_providers ||= cfg.dig(:service_providers)&.each_with_object({}) do |sp_config, hash|
            sp = SAML2::ServiceProvider.new
            sp.want_assertions_signed = true

            # ACS:
            sp_config.dig(:assertion_consumer_services)&.each_with_index do |acs_config, index|
                sp.assertion_consumer_services << SAML2::Endpoint::Indexed.new(acs_config[:location], index, index == 0, acs_config[:binding])
            end || []

            # the other, worse kind of ACS:
            sp_config.dig(:attribute_consuming_services)&.each_with_index do |acs_config, index|
                requested_attributes = []
                acs_config.dig(:requested_attributes)&.each do |attr_config|
                    requested_attr = SAML2::RequestedAttribute.create(
                        attr_config[:name],
                        attr_config[:is_required]
                    )
                    requested_attr.name_format = attr_config[:name_format] if attr_config[:name_format]
                    requested_attributes << requested_attr
                end
                acs = SAML2::AttributeConsumingService.new(acs_config[:name], requested_attributes)
                acs.index = index
                acs.instance_variable_set(:@is_default, index == 0)
                sp.attribute_consuming_services << acs
            end

            ent = SAML2::Entity.new
            ent.entity_id = sp_config[:entity_id]
            ent.instance_variable_set(:@roles, [ sp ])

            hash[sp_config[:entity_id]] = {
                display_name: sp_config[:friendly_name],
                friendly_name: sp_config[:friendly_name],
                tagline: sp_config[:tagline],
                icon: sp_config[:icon],
                entity: ent,
                entity_id: sp_config[:entity_id],
                allow_idp_initiated: sp_config[:allow_idp_initiated],
                allow_unsigned_requests: sp_config[:allow_unsigned_requests] || false,
                attribute_format: sp_config[:attribute_format]&.to_sym || :default,
                allowed_attributes: sp_config[:allowed_attributes],
                allowed_emails: sp_config[:allowed_emails],
                signing_certificate: load_sp_certificate(sp_config[:signing_certificate]),
                slug: sp_config[:slug]
            }
            end || {}
        end

        def sp_by_entity_id(entity_id) = service_providers[entity_id]

        def sp_by_slug(slug) = service_providers.values.find { |sp_data| sp_data[:slug] == slug }

        def x509_certificate
            @cert ||= begin
                return nil unless (cert_path = ENV["SAML_IDP_CERT_PATH"])
                File.read(cert_path)
                    .gsub(/-----(BEGIN|END) CERTIFICATE-----/, "")
                    .gsub(/\n/, "")
            end
        end

        def private_key
            @key ||= begin
                return nil unless (key_path = ENV["SAML_IDP_KEY_PATH"])
                File.read(key_path)
            end
        end

        def signing_key
            @signing_key ||= begin
                return nil unless x509_certificate && private_key

                SAML2::KeyDescriptor.new(x509_certificate, SAML2::KeyDescriptor::Type::SIGNING)
            end
        end

        def validate_keys!
            raise "SAML IdP private key not configured. Set SAML_IDP_KEY_PATH environment variable." unless private_key.present?
            raise "SAML IdP certificate not configured. Set SAML_IDP_CERT_PATH environment variable." unless x509_certificate.present?

            # Verify key and cert match
            cert = OpenSSL::X509::Certificate.new("-----BEGIN CERTIFICATE-----\n#{x509_certificate}\n-----END CERTIFICATE-----")
            key = OpenSSL::PKey::RSA.new(private_key)

            unless cert.check_private_key(key)
              raise "SAML IdP certificate and private key do not match!"
            end

            true
          rescue OpenSSL::PKey::PKeyError, OpenSSL::X509::CertificateError => e
            raise "Invalid SAML IdP certificate or key: #{e.message}"
        end

        private

        def load_sp_certificate(cert_config)
            return nil unless cert_config.present?

            if cert_config.is_a?(String) && cert_config.start_with?("file://")
              path = cert_config.sub("file://", "")
              File.read(path).gsub(/-----(BEGIN|END) CERTIFICATE-----/, "").gsub(/\n/, "")
            elsif cert_config.is_a?(String)
              cert_config.gsub(/-----(BEGIN|END) CERTIFICATE-----/, "").gsub(/\n/, "")
            end
          rescue => e
            Rails.logger.error "Failed to load SP certificate: #{e.message}"
            nil
        end

        def yaml_to_saml(yaml, saml)
            yaml.each do |key, value|
              saml.send("#{key}=", value)
              end
            saml
        end

        def cfg = Rails.application.config.saml

        def idp_meta = cfg.dig(:idp_metadata)
        end
    end
end
