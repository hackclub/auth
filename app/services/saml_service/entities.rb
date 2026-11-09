module SAMLService
    module Entities
        # Signing state as of one SAMLCertificate.version: cert, parsed key and rollover cert read
        # together, plus anything built from them (idp, metadata). Swapped whole, never mutated piecemeal,
        # so a request can't end up with one cert's key and another's KeyInfo.
        class Keys
            attr_reader :version, :certificate, :private_key, :rollover_certificate

            def initialize(version:, certificate: nil, private_key: nil, rollover_certificate: nil)
                @version = version
                @certificate = certificate
                @private_key = private_key
                @rollover_certificate = rollover_certificate
                @memo = {}
            end

            def signing? = certificate.present? && private_key.present?

            def memo(name) = @memo.fetch(name) { @memo[name] = yield }
        end

        LOCK = Mutex.new

        class << self
        # one cheap max(updated_at) per call; rebuilds when any worker (or a console) rotated
        def keys
            version = SAMLCertificate.version
            current = @keys
            return current if current && current.version == version

            LOCK.synchronize do
                @keys = load_keys(version) unless @keys && @keys.version == version
                @keys
            end
        end

        # returns a SAML2::IdentityProvider object
        def idp = idp_for(keys)

        def idp_entity = idp_entity_for(keys)

        def metadata_xml
            k = keys
            k.memo(:metadata_xml) do
                xml = idp_entity_for(k).to_xml
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

        # Bust the snapshot in this process; other processes notice via SAMLCertificate.version
        def reset! = @keys = nil

        private

        # DB-backed with env var fallback. Both roles in one query so a promote can't land between them.
        def load_keys(version)
            certs = SAMLCertificate.where(role: %w[signing rollover]).order(:id).to_a if version
            signing = certs&.find(&:signing?)
            rollover = certs&.find(&:rollover?)

            if signing
                Keys.new(version:, certificate: signing.x509_certificate_base64, private_key: signing.private_key,
                         rollover_certificate: rollover&.x509_certificate_base64)
            elsif (cert_path = ENV["SAML_IDP_CERT_PATH"]) && (key_path = ENV["SAML_IDP_KEY_PATH"])
                Keys.new(version:,
                         certificate: Base64.strict_encode64(OpenSSL::X509::Certificate.new(File.read(cert_path)).to_der),
                         private_key: OpenSSL::PKey::RSA.new(File.read(key_path)),
                         rollover_certificate: rollover&.x509_certificate_base64)
            else
                Keys.new(version:, rollover_certificate: rollover&.x509_certificate_base64)
            end
        end

        def idp_entity_for(k)
            k.memo(:idp_entity) do
                ent = SAML2::Entity.new
                ent.entity_id = idp_meta.dig(:entity_id)
                ent.instance_variable_set(:@roles, [ idp_for(k) ])
                ent
            end
        end

        def idp_for(k) = k.memo(:idp) { build_idp(k) }

        def build_idp(k)
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

            idp.keys << SAML2::KeyDescriptor.new(k.certificate, SAML2::KeyDescriptor::Type::SIGNING) if k.signing?
            # rollover cert published in metadata so SPs can pre-trust it
            if k.rollover_certificate
                idp.keys << SAML2::KeyDescriptor.new(k.rollover_certificate, SAML2::KeyDescriptor::Type::SIGNING)
            end

            idp
        end

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
