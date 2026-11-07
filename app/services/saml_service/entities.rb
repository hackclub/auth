module SAMLService
    module Entities
        # Raised when a service_providers entry in config/saml.yml can't be loaded as written.
        class ConfigError < StandardError; end

        # Every key a service_providers entry may set. Anything else raises: a key the loader
        # doesn't know about would otherwise be dropped without a word, which is how
        # required_entitlements once switched its own gate off.
        SP_CONFIG_KEYS = %i[
            slug entity_id friendly_name tagline icon
            assertion_consumer_services attribute_consuming_services
            allow_idp_initiated allow_unsigned_requests signing_certificate
            attribute_format allowed_attributes allowed_emails
            required_entitlements entitlements groups_attribute
        ].freeze

        DEFAULT_GROUPS_ATTRIBUTE = "groups"

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
            @service_providers ||= build_service_providers(cfg.dig(:service_providers))
        end

        def reset!
            @idp = @idp_entity = @metadata_xml = @service_providers = nil
            @cert = @key = @signing_key = nil
        end

        # { entity_id => sp_config } from a service_providers list, as config_for(:saml) returns it.
        # Raises ConfigError rather than load an SP differently from how it's written.
        def build_service_providers(sp_configs)
            return {} if sp_configs.nil?
            raise ConfigError, "SAML service_providers must be a list, got #{sp_configs.inspect}" unless sp_configs.is_a?(Array)

            sp_configs.each_with_object({}) do |sp_config, hash|
            check_sp_entry!(sp_config, hash)
            label = sp_config[:slug]

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

            entitlements = sp_entitlements(sp_config, label)
            groups_attribute = sp_groups_attribute(sp_config, label)
            check_groups_attribute_reaches_sp!(sp_config, sp, groups_attribute, label) if entitlements.any?

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
                allowed_emails: sp_string_list(sp_config, :allowed_emails, label),
                signing_certificate: load_sp_certificate(sp_config[:signing_certificate]),
                slug: sp_config[:slug],
                required_entitlements: sp_string_list(sp_config, :required_entitlements, label),
                entitlements: entitlements,
                groups_attribute: groups_attribute
            }
            end
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

        # The checks that need the raw entry or the SPs loaded before it: shape, unknown keys,
        # the two identifiers, and that neither is reused (a reused entity_id would let the
        # later entry silently replace the earlier one, requirements and all).
        def check_sp_entry!(sp_config, loaded)
            raise ConfigError, "SAML service_providers entries must be mappings, got #{sp_config.inspect}" unless sp_config.is_a?(Hash)

            label = sp_config[:slug] || sp_config[:entity_id] || "(no slug)"
            unknown_keys = sp_config.keys - SP_CONFIG_KEYS
            if unknown_keys.any?
                raise ConfigError, "SAML SP #{label}: unknown key #{unknown_keys.join(', ')} (known keys: #{SP_CONFIG_KEYS.join(', ')})"
            end

            %i[slug entity_id].each do |key|
                raise ConfigError, "SAML SP #{label}: #{key} is required" unless sp_config[key].is_a?(String) && sp_config[key].present?
            end
            if loaded.key?(sp_config[:entity_id])
                raise ConfigError, "SAML SP #{label}: entity_id #{sp_config[:entity_id]} is already used by another SP"
            end
            if loaded.each_value.any? { |other| other[:slug] == sp_config[:slug] }
                raise ConfigError, "SAML SP #{label}: slug is already used by another SP"
            end
        end

        # allowed_emails and required_entitlements: one string or a list of them, [] when absent.
        # A key that's present but empty raises instead of reading as "no restriction", since
        # that would open the SP to everyone. (A bare string is wrapped so it's matched exactly
        # and not through String#include?.)
        def sp_string_list(sp_config, key, label)
            return [] unless sp_config.key?(key)

            list = Array.wrap(sp_config[key])
            unless list.any? && list.all? { |item| item.is_a?(String) && item.present? }
                raise ConfigError, "SAML SP #{label}: #{key} must be a string or a list of strings with at least one entry, got #{sp_config[key].inspect}"
            end

            list.uniq.freeze
        end

        # entitlement slug => the value the SP sees for it in the groups attribute
        def sp_entitlements(sp_config, label)
            entitlements = sp_config[:entitlements]
            return {} if entitlements.nil?

            unless entitlements.is_a?(Hash) && entitlements.each_value.all? { |value| value.is_a?(String) && value.present? }
                raise ConfigError, "SAML SP #{label}: entitlements must map entitlement slugs to the value the SP sees, got #{entitlements.inspect}"
            end

            entitlements.to_h { |slug, value| [ slug.to_s, value ] }.freeze
        end

        def sp_groups_attribute(sp_config, label)
            name = sp_config[:groups_attribute]
            return DEFAULT_GROUPS_ATTRIBUTE if name.nil?
            return name if name.is_a?(String) && name.present?

            raise ConfigError, "SAML SP #{label}: groups_attribute must be an attribute name, got #{name.inspect}"
        end

        # SAMLHelper adds the groups attribute only if allowed_attributes lets it through, and the
        # SAML2 gem then keeps only the attributes an SP's attribute_consuming_services request.
        # If either drops it, the SP never sees its entitlements, so refuse the config instead.
        def check_groups_attribute_reaches_sp!(sp_config, sp, attr_name, label)
            allowed_attributes = sp_config[:allowed_attributes]
            if allowed_attributes.present? && !Array.wrap(allowed_attributes).include?(attr_name)
                raise ConfigError, "SAML SP #{label}: has entitlements, but allowed_attributes doesn't include #{attr_name}, so they'd never be sent"
            end

            if sp.attribute_consuming_services.empty?
                raise ConfigError, "SAML SP #{label}: has entitlements but no attribute_consuming_services, so it's sent no attributes at all. add one whose requested_attributes include #{attr_name}"
            end

            unless sp.attribute_consuming_services.all? { |acs| acs.requested_attributes.any? { |attr| attr.name == attr_name } }
                raise ConfigError, "SAML SP #{label}: has entitlements, but #{attr_name} isn't in the requested_attributes of every attribute_consuming_service, so the SAML2 gem would drop it"
            end
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
