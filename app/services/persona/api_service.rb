class Persona::APIService
  BASE_URL = "https://withpersona.com"

  def initialize(api_key:)
    @api_key = api_key
  end

  def create_inquiry(template_id:, account_reference_id:)
    data, included = request!(:post, "/api/v1/inquiries") do |req|
      req.body = {
        data: {
          attributes: {
            inquiry_template_id: template_id
          }
        },
        meta: {
          auto_create_account: true,
          auto_create_account_reference_id: account_reference_id,
          auto_create_inquiry_session: true
        }
      }
    end

    session = included.find { |i| i[:type] == "inquiry-session" }

    build_inquiry(data, session)
  end

  def retrieve_inquiry(inquiry_id)
    data, included = request!(:get, "/api/v1/inquiries/#{inquiry_id}")
    session = included.find { |i| i[:type] == "inquiry-session" }

    build_inquiry(data, session)
  end

  def retrieve_government_id_verification(verification_id)
    data, _ = request!(:get, "/api/v1/verification/government-ids/#{verification_id}")
    attrs = data[:attributes]

    Persona::GovernmentIdVerification.new(
      id: data[:id],
      status: attrs[:status],
      name_first: attrs[:name_first],
      name_last: attrs[:name_last],
      birthdate: attrs[:birthdate] ? Date.parse(attrs[:birthdate]) : nil,
      country_code: attrs[:address_country_code],
      front_photo: attrs[:front_photo],
      back_photo: attrs[:back_photo],
      selfie_photo: attrs[:selfie_photo]
    )
  end

  def download_file(file_id)
    response = connection.get("/api/v1/files/#{file_id}")
    raise Persona::APIError, error_message(response) unless response.success?

    StringIO.new(response.body)
  end

  private

  def request!(method, path, &block)
    response = connection.send(method, path, &block)
    raise Persona::APIError, error_message(response) unless response.success?

    body = response.body.deep_symbolize_keys
    [body[:data], body[:included] || []]
  end

  def connection
    @connection ||= Faraday.new(
      url: BASE_URL,
      headers: {
        "Authorization" => "Bearer #{@api_key}",
        "Persona-Version" => "2025-12-08",
        "Key-Inflection" => "snake"
      },
      request: { timeout: 30, open_timeout: 10 }
    ) do |f|
      f.request :json
      f.response :json
      f.adapter Faraday.default_adapter
    end
  end

  def build_inquiry(data, session)
    verifications = data.dig(:relationships, :verifications, :data) || []

    Persona::Inquiry.new(
      id: data[:id],
      status: data.dig(:attributes, :status),
      account_id: data.dig(:relationships, :account, :data, :id),
      session_token: session&.dig(:attributes, :session_token),
      verification_ids: verifications
    )
  end

  def error_message(response)
    errors = response.body.is_a?(Hash) ? response.body["errors"] : nil
    if errors&.any?
      errors.map { |e| e["title"] || e["detail"] }.compact.join(", ")
    else
      "Persona API error (#{response.status})"
    end
  end
end
