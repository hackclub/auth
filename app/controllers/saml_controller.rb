class SAMLController < ApplicationController
  include SAMLHelper

  skip_before_action :authenticate_identity!, only: [ :metadata, :sp_initiated_get, :idp_initiated, :welcome ]

  AUTHN_REQUEST_TTL = 5.minutes
  SSO_ENDPOINT_PATH = "/saml/auth"

  def metadata
    xml = SAMLService::Entities.metadata_xml
    render xml:
  end

  def idp_initiated

    if Rails.env.staging? && params[:slug] == "slack"
      render "static_pages/slack_staging" and return
    end
    
    return unless ensure_sp_configured!(slug: params[:slug])

    unless @sp_config[:allow_idp_initiated]
      @error = "This SP is not configured for IdP-initiated authentication"
      render :error and return
    end

    unless current_identity
      session[:saml_return_to] = request.original_url
      redirect_to saml_welcome_path and return
    end

    response = build_saml_response(
      identity: current_identity,
      sp_config: @sp_config,
      in_response_to: nil
    )

    render_saml_response(saml_response: response, sp_config: @sp_config)
  end

  def sp_initiated_get
    @authn_request, @relay_state = SAML2::Bindings::HTTPRedirect.decode(request.url)
    return unless ensure_sp_configured!(entity_id: @authn_request.issuer.id)
    return unless ensure_authn_request_valid!
    return unless verify_authn_request_signature!
    return unless check_replay!

    response = build_saml_response(
      identity: current_identity,
      sp_config: @sp_config,
      in_response_to: @authn_request
    )

    render_saml_response(saml_response: response, sp_config: @sp_config)
  end

  private

  def verify_authn_request_signature!
    return true if @sp_config[:allow_unsigned_requests]

    unless @sp_config[:signing_certificate].present?
      @error = "SP signature verification required but no signing certificate configured"
      render :error, status: :bad_request and return false
    end

    query_string = URI(request.url).query
    query_params = Rack::Utils.parse_query(query_string)

    unless query_params["Signature"].present?
      @error = "AuthnRequest signature required but not provided"
      render :error, status: :unauthorized and return false
    end

    begin
      cert = OpenSSL::X509::Certificate.new(
        "-----BEGIN CERTIFICATE-----\n#{@sp_config[:signing_certificate]}\n-----END CERTIFICATE-----"
      )

      signed_query = query_string.split("&Signature=").first
      signature_bytes = Base64.decode64(query_params["Signature"])

      digest = case query_params["SigAlg"]
      when "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256"
        OpenSSL::Digest::SHA256.new
      when "http://www.w3.org/2000/09/xmldsig#rsa-sha1"
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
end
