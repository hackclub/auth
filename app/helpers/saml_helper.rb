module SAMLHelper
  def build_saml_response(identity:, sp_config:, in_response_to: nil)
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

  def saml_issuer
    @saml_issuer ||= SAML2::NameID.new(SAMLService::Entities.idp_entity.entity_id)
  end

  def saml_filtered_attributes(identity, sp_config)
    all_attrs = identity.to_saml_attributes

    if sp_config[:allowed_attributes].present?
      allowed = sp_config[:allowed_attributes]
      all_attrs.select { |attr| allowed.include?(attr.name) }
    else
      all_attrs
    end
  end
end
