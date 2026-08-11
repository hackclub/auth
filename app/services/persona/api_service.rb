class Persona::APIService
  BASE_URL = "https://api.withpersona.com"

  def initialize(api_key:) = @api_key = api_key

  def create_inquiry(template_id:, account_reference_id:, fields: {})
    data, meta = request!(:post, "/api/v1/inquiries") do |req|
      body = {
        data: { attributes: { inquiry_template_id: template_id } },
        meta: {
          auto_create_account: true,
          auto_create_account_reference_id: account_reference_id,
          auto_create_inquiry_session: true
        }
      }
      body[:data][:attributes][:fields] = fields if fields.any?
      req.body = body
    end

    build_inquiry(data, session_token: meta[:session_token])
  end

  def retrieve_inquiry(inquiry_id)
    response = connection.get("/api/v1/inquiries/#{inquiry_id}?include=sessions")
    raise Persona::APIError, error_message(response) unless response.success?

    body = response.body.deep_symbolize_keys
    included = body[:included] || []
    sessions = included
      .select { |obj| obj[:type] == "inquiry-session" }
      .map { |obj| obj[:attributes] || {} }

    build_inquiry(body[:data], session_token: body.dig(:meta, :session_token), sessions: sessions)
  end

  def resume_inquiry(inquiry_id)
    data, meta = request!(:post, "/api/v1/inquiries/#{inquiry_id}/resume")
    build_inquiry(data, session_token: meta[:session_token])
  end

  def expire_inquiry(inquiry_id)
    data, meta = request!(:post, "/api/v1/inquiries/#{inquiry_id}/expire")
    build_inquiry(data, session_token: meta[:session_token])
  end

  def retrieve_government_id_verification(verification_id)
    data, _ = request!(:get, "/api/v1/verification/government-ids/#{verification_id}")
    attrs = data[:attributes]

    Persona::GovernmentIdVerification.new(
      id:                       data[:id],
      status:                   attrs[:status],
      name_first:               attrs[:name_first],
      name_last:                attrs[:name_last],
      birthdate:                attrs[:birthdate] ? Date.parse(attrs[:birthdate]) : nil,
      country_code:             attrs[:country_code],
      id_class:                 attrs[:id_class],
      expiration_date:          attrs[:expiration_date] ? Date.parse(attrs[:expiration_date]) : nil,
      entity_confidence_score:  attrs[:entity_confidence_score]&.then { |s| s > 1 ? s / 100.0 : s },
      checks:                   attrs[:checks] || [],
      front_photo:              attrs[:front_photo],
      back_photo:               attrs[:back_photo],
      selfie_photo:             attrs[:selfie_photo],
      raw:                      attrs
    )
  end

  def retrieve_document_photos(document_id, type:)
    case type
    when "document/government-id"
      attrs = fetch_resource("document/government-ids", document_id)
      Persona::PhotoSet.new(
        document: [ attrs[:front_photo], attrs[:back_photo] ].filter_map { |p| photo(p) },
        liveness: []
      )
    else
      attrs = fetch_resource("documents", document_id)
      Persona::PhotoSet.new(
        document: (attrs[:files] || []).each_with_index.map { |f, i| f.merge(label: "file_#{i + 1}") },
        liveness: []
      )
    end
  end

  def retrieve_verification_photos(verification_id, type:)
    case type
    when "verification/selfie"
      attrs = fetch_resource("verification/selfies", verification_id)
      Persona::PhotoSet.new(
        document: [],
        liveness: %i[center left right].filter_map { |dir|
          url = attrs[:"#{dir}_photo_url"]
          { url: url, label: "selfie_#{dir}" } if url.is_a?(String)
        }
      )
    else
      Persona::PhotoSet.empty
    end
  end

  def redact_account(account_id) = request!(:delete, "/api/v1/accounts/#{account_id}")

  ALLOWED_DOWNLOAD_HOSTS = %w[files.withpersona.com withpersona.com].freeze

  def download_file(url)
    uri = URI.parse(url)
    unless uri.scheme == "https" && ALLOWED_DOWNLOAD_HOSTS.include?(uri.host)
      raise Persona::APIError, "refusing to download from untrusted host: #{uri.host}"
    end

    response = file_connection(uri.host).get(uri.request_uri)
    raise Persona::APIError, "failed to download file (#{response.status})" unless response.success?
    StringIO.new(response.body)
  end

  private

  def request!(method, path, &block)
    response = connection.send(method, path, &block)
    unless response.success?
      msg = error_message(response)
      raise Persona::ConflictError, msg if response.status == 409
      raise Persona::APIError, msg
    end

    body = response.body.deep_symbolize_keys
    [ body[:data], body[:meta] || {} ]
  end

  def file_connection(host)
    @file_connections ||= {}
    @file_connections[host] ||= Faraday.new(
      url: "https://#{host}",
      request: { timeout: 30, open_timeout: 10 }
    ) { |f| f.request :retry, max: 2, retry_statuses: [ 502, 503, 504 ] }
  end

  def connection
    @connection ||= Faraday.new(
      url: BASE_URL,
      headers: {
        "Authorization"  => "Bearer #{@api_key}",
        "Persona-Version" => "2025-12-08",
        "Key-Inflection"  => "snake"
      },
      request: { timeout: 30, open_timeout: 10 }
    ) do |f|
      f.request  :json
      f.response :json
      f.adapter  Faraday.default_adapter
    end
  end

  def build_inquiry(data, session_token: nil, sessions: [])
    verifications = data.dig(:relationships, :verifications, :data) || []
    documents = data.dig(:relationships, :documents, :data) || []

    Persona::Inquiry.new(
      id:               data[:id],
      status:           data.dig(:attributes, :status),
      account_id:       data.dig(:relationships, :account, :data, :id),
      session_token:    session_token,
      verification_ids: verifications,
      document_ids:     documents,
      behaviors:        data.dig(:attributes, :behaviors) || {},
      sessions:         sessions,
      raw:              data[:attributes] || {}
    )
  end

  def fetch_resource(endpoint, id)
    data, _ = request!(:get, "/api/v1/#{endpoint}/#{id}")
    data[:attributes]
  end

  def photo(data)
    return nil unless data.is_a?(Hash) && data[:url]
    data
  end

  def error_message(response)
    errors = response.body.is_a?(Hash) ? response.body["errors"] : nil
    return "Persona API error (#{response.status})" unless errors&.any?
    errors.map { |e| e["title"] || e["detail"] }.compact.join(", ")
  end
end
