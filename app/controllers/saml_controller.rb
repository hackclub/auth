require 'ruby-saml'

class SAMLController < ApplicationController
  skip_before_action :authenticate_identity!, only: [:metadata]

  AUTHN_REQUEST_TTL = 5.minutes
  SSO_ENDPOINT_PATH = '/saml/auth'

  def metadata
    render xml: SAMLService::Entities.idp_entity.to_xml
  end

  def idp_initiated
    return unless ensure_sp_configured!(slug: params[:slug])

    unless @sp_config[:allow_idp_initiated]
      @error = "This SP is not configured for IdP-initiated authentication"
      render :error and return
    end

    response = build_response(
      @sp_config[:entity].service_providers.first,
      nil # no InResponseTo for IdP-initiated
    )

    pass_response_to_sp(response)
  end

  def sp_initiated_get
    @authn_request, @relay_state = SAML2::Bindings::HTTPRedirect.decode(request.url)
    return unless ensure_sp_configured!(entity_id: @authn_request.issuer.id)
    return unless ensure_authn_request_valid!
    return unless verify_authn_request_signature!
    return unless check_replay!

    response = build_response(
      @sp_config[:entity].service_providers.first,
      @authn_request
    )

    pass_response_to_sp(response)
  end

  private

  def build_response(sp, in_response_to)
    if in_response_to
      response = SAML2::Response.respond_to(
        in_response_to,
        issuer,
        current_identity.to_saml_nameid,
        filtered_attributes
      )
    else
      # IdP-initiated
      response = SAML2::Response.initiate(sp, issuer, current_identity.to_saml_nameid, filtered_attributes)
    end

    # Extend TTLs from default 30s to 5 minutes for better compatibility
    now = Time.now.utc
    response.assertions.each do |assertion|
      assertion.conditions.not_on_or_after = now + 5.minutes
      assertion.subject.confirmation.not_on_or_after = now + 5.minutes
    end

    response
  end

  def filtered_attributes
    all_attrs = current_identity.to_saml_attributes
    
    # Apply per-SP attribute whitelist if configured
    if @sp_config[:allowed_attributes].present?
      allowed = @sp_config[:allowed_attributes]
      all_attrs.select { |attr| allowed.include?(attr.name) }
    else
      all_attrs
    end
  end

  def pass_response_to_sp(saml_response)
    # TODO: HTTP redirect binding support? didn't build it because we don't need it but maybe someday
    signed_xml = SAMLService::Signing.sign_response(saml_response)
    @saml_response = Base64.strict_encode64(signed_xml.to_s)
    @saml_acs_url = @sp_config[:entity].service_providers.first.assertion_consumer_services.default.location
    
    if Rails.env.production? && URI(@saml_acs_url).scheme != 'https'
      @error = "ACS URL must use HTTPS in production"
      render :error, status: :bad_request and return
    end

    response.headers['Cache-Control'] = 'no-store, no-cache, must-revalidate'
    response.headers['Pragma'] = 'no-cache'

    render template: "saml/http_post", layout: "minimal"
  end

  def verify_authn_request_signature!
    return true if @sp_config[:allow_unsigned_requests]

    unless @sp_config[:signing_certificate].present?
      @error = "SP signature verification required but no signing certificate configured"
      render :error, status: :bad_request and return false
    end

    query_string = URI(request.url).query
    query_params = Rack::Utils.parse_query(query_string)
    
    unless query_params['Signature'].present?
      @error = "AuthnRequest signature required but not provided"
      render :error, status: :unauthorized and return false
    end

    begin
      cert = OpenSSL::X509::Certificate.new(
        "-----BEGIN CERTIFICATE-----\n#{@sp_config[:signing_certificate]}\n-----END CERTIFICATE-----"
      )
      
      signed_query = query_string.split('&Signature=').first
      signature_bytes = Base64.decode64(query_params['Signature'])
      
      digest = case query_params['SigAlg']
      when 'http://www.w3.org/2001/04/xmldsig-more#rsa-sha256'
        OpenSSL::Digest::SHA256.new
      when 'http://www.w3.org/2000/09/xmldsig#rsa-sha1'
        OpenSSL::Digest::SHA1.new
      else
        raise "Unsupported signature algorithm: #{query_params['SigAlg']}"
      end
      
      verified = cert.public_key.verify(digest, signature_bytes, signed_query)

      unless verified
        @error = "AuthnRequest signature verification failed"
        render :error, status: :unauthorized and return false
      end

      true
    rescue => e
      Rails.logger.error "SAML signature verification error: #{e.message}"
      @error = "AuthnRequest signature verification failed"
      render :error, status: :unauthorized and return false
    end
  end

  def check_replay!
    request_id = @authn_request.id
    cache_key = "saml:authn_request:#{request_id}"
    
    if Rails.cache.exist?(cache_key)
      @error = "AuthnRequest has already been processed (replay detected)"
      render :error, status: :bad_request and return false
    end

    # Cache the request ID for the TTL window
    Rails.cache.write(cache_key, true, expires_in: AUTHN_REQUEST_TTL)
    true
  end

  def ensure_authn_request_valid!
    unless @authn_request.is_a?(SAML2::AuthnRequest)
      @error = "SAML request is not a valid AuthnRequest"
      render :error, status: :bad_request and return false
    end

    unless @authn_request.valid_schema?
      @error = "SAML AuthnRequest does not conform to the required XML schema"
      render :error, status: :bad_request and return false
    end

    unless @authn_request.valid_interoperable_profile?
      @error = "SAML AuthnRequest does not conform to the SAML2 Interoperable Profile"
      render :error, status: :bad_request and return false
    end

    unless @authn_request.resolve(@sp_config[:entity].service_providers.first)
      @error = "SAML AuthnRequest could not be resolved for this Service Provider"
      render :error, status: :bad_request and return false
    end

    expected_destination = request.base_url + SSO_ENDPOINT_PATH
    if @authn_request.destination.present? && @authn_request.destination != expected_destination
      @error = "AuthnRequest Destination does not match IdP SSO endpoint"
      render :error, status: :bad_request and return false
    end

    # Validate IssueInstant is within acceptable time window
    if @authn_request.issue_instant
      issue_time = @authn_request.issue_instant
      now = Time.now.utc
      
      if issue_time > now + 1.minute # Allow 1 min clock skew forward
        @error = "AuthnRequest IssueInstant is in the future"
        render :error, status: :bad_request and return false
      end
      
      if issue_time < now - AUTHN_REQUEST_TTL
        @error = "AuthnRequest has expired"
        render :error, status: :bad_request and return false
      end
    end

    true
  end

  def ensure_sp_configured!(entity_id: nil, slug: nil)
    return unless entity_id || slug

    if slug.present?
      @sp_config = SAMLService::Entities.sp_by_slug(slug)
    else
      @sp_config = SAMLService::Entities.sp_by_entity_id(entity_id)
    end

    unless @sp_config.present?
      @error = "Service Provider not configured"
      render :error, status: :bad_request and return false
    end

    true
  end

  def issuer
    @issuer ||= SAML2::NameID.new(SAMLService::Entities.idp_entity.entity_id)
  end
end
