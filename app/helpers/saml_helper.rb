module SAMLHelper
  # Raised by build_saml_response when the identity may not have an assertion for the SP.
  # The message is the reason, fit to show them.
  class AccessDenied < StandardError; end

  # Every assertion is built here, so this is where access is enforced: a path that never
  # checks (LoginsController's post-signup Slack login used to be one) still can't get one.
  def build_saml_response(identity:, sp_config:, in_response_to: nil)
    if (reason = saml_access_denial(identity, sp_config))
      raise AccessDenied, reason
    end

    sp = sp_config[:entity].service_providers.first

    if in_response_to
      saml_response = SAML2::Response.respond_to(
        in_response_to,
        saml_issuer,
        identity.to_saml_nameid,
        saml_filtered_attributes(identity, sp_config)
      )
    else
      saml_response = SAML2::Response.initiate(
        sp,
        saml_issuer,
        identity.to_saml_nameid,
        saml_filtered_attributes(identity, sp_config)
      )
      saml_response.assertions.first.conditions << SAML2::Conditions::AudienceRestriction.new(sp_config[:entity].entity_id)
    end

    now = Time.now.utc
    saml_response.assertions.each do |assertion|
      assertion.conditions.not_on_or_after = now + 5.minutes
      assertion.subject.confirmation.not_on_or_after = now + 5.minutes
    end

    saml_response
  end

  def render_saml_response(saml_response:, sp_config:)
    signed_xml = SAMLService::Signing.sign_response(saml_response)
    @saml_response = Base64.strict_encode64(signed_xml.to_s)
    @saml_acs_url = sp_config[:entity].service_providers.first.assertion_consumer_services.default.location

    if Rails.env.production? && URI(@saml_acs_url).scheme != "https"
      @error = "ACS URL must use HTTPS in production"
      render :error, status: :bad_request and return
    end

    if current_identity
      current_identity.create_activity :saml_login, owner: current_identity, recipient: current_identity,
        parameters: { service_provider: sp_config[:slug], name: sp_config[:friendly_name] }
    end

    response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate"
    response.headers["Pragma"] = "no-cache"

    render template: "saml/http_post", layout: "minimal"
  end

  def pretty_xml(xml_string)
    return "nil" if xml_string.nil?
    require "rexml/document"
    doc = REXML::Document.new(xml_string)
    formatter = REXML::Formatters::Pretty.new(2)
    formatter.compact = true
    out = ""
    formatter.write(doc, out)
    out
  rescue
    xml_string
  end

  private

  # Why +identity+ may not have an assertion for +sp_config+, or nil if it may.
  # build_saml_response enforces this; SAMLController also asks first, so it can show the
  # error before doing anything else.
  def saml_access_denial(identity, sp_config)
    if sp_config[:allowed_emails].present? && !sp_config[:allowed_emails].include?(identity.primary_email)
      return "You are not authorized to access this service"
    end

    if (reason = saml_directory_requirement_denial(identity, sp_config))
      return reason
    end

    "Unable to log in right now" if sp_config[:slug] == "slack" && identity.disallow_slack
  end

  # required_entitlements: any one of them admits. A slug that doesn't resolve shuts
  # everyone out (SPEC §7.2) rather than quietly shrinking the list.
  def saml_directory_requirement_denial(identity, sp_config)
    required = sp_config[:required_entitlements]
    return if required.blank?

    entitlements = Directory::Collection.entitlements.where(slug: required)
    missing_slugs = required - entitlements.pluck(:slug)

    if missing_slugs.any?
      Rails.logger.error("[SAML] required_entitlements references missing slugs: #{missing_slugs.join(', ')} for SP #{sp_config[:slug]}")
      Sentry.capture_message("SAML requirement references missing entitlement", level: :error, extra: { sp: sp_config[:slug], missing_slugs: missing_slugs }) if defined?(Sentry)
      return "this app is misconfigured — contact an administrator"
    end

    person = Directory::Person.find_by(identity: identity)
    unless person && Directory::EffectiveMembership.where(collection_id: entitlements.select(:id), person_id: person.id).exists?
      "this app is for hack club staff"
    end
  end

  def saml_issuer
    @saml_issuer ||= SAML2::NameID.new(SAMLService::Entities.idp_entity.entity_id)
  end

  def saml_filtered_attributes(identity, sp_config)
    all_attrs = identity.to_saml_attributes

    if sp_config[:allowed_attributes].present?
      allowed = sp_config[:allowed_attributes]
      all_attrs = all_attrs.select { |attr| allowed.include?(attr.name) }
    end

    groups_values = saml_directory_groups(identity, sp_config)
    if groups_values.any?
      attr_name = sp_config[:groups_attribute] || "groups"
      if sp_config[:allowed_attributes].blank? || sp_config[:allowed_attributes].include?(attr_name)
        all_attrs << SAML2::Attribute.new(attr_name, groups_values)
      end
    end

    all_attrs
  end

  def saml_directory_groups(identity, sp_config)
    entitlements_map = sp_config[:entitlements]
    return [] if entitlements_map.blank?

    person = Directory::Person.find_by(identity: identity)
    return [] unless person

    slugs = entitlements_map.keys.map(&:to_s)
    entitled_slugs = Directory::EffectiveMembership
      .joins(:collection)
      .where(person_id: person.id, directory_collections: { slug: slugs, kind: "entitlement" })
      .pluck("directory_collections.slug")

    entitled_slugs.filter_map { |slug| entitlements_map[slug] }
  end
end
