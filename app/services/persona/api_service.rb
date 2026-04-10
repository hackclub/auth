class Persona::APIService
  BASE_URL = "https://withpersona.com"

  def initialize(api_key:)
    @api_key = api_key
  end

  def create_inquiry(template_id:, account_reference_id:)
    response = connection.post("/api/v1/inquiries") do |req|
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

    raise Persona::APIError, error_message(response) unless response.success?

    data = response.body["data"]
    included = response.body["included"] || []
    session = included.find { |i| i["type"] == "inquiry-session" }

    Persona::Inquiry.new(
      id: data["id"],
      status: data.dig("attributes", "status"),
      account_id: data.dig("relationships", "account", "data", "id"),
      session_token: session&.dig("attributes", "session_token")
    )
  end

  def retrieve_inquiry(inquiry_id)
    response = connection.get("/api/v1/inquiries/#{inquiry_id}")

    raise Persona::APIError, error_message(response) unless response.success?

    data = response.body["data"]
    included = response.body["included"] || []
    session = included.find { |i| i["type"] == "inquiry-session" }

    Persona::Inquiry.new(
      id: data["id"],
      status: data.dig("attributes", "status"),
      account_id: data.dig("relationships", "account", "data", "id"),
      session_token: session&.dig("attributes", "session_token")
    )
  end

  def retrieve_government_id_verification(verification_id)
    response = connection.get("/api/v1/verification/government-ids/#{verification_id}")

    raise Persona::APIError, error_message(response) unless response.success?

    attrs = response.body.dig("data", "attributes")

    Persona::GovernmentIdVerification.new(
      id: response.body.dig("data", "id"),
      status: attrs["status"],
      name_first: attrs["name_first"],
      name_last: attrs["name_last"],
      birthdate: attrs["birthdate"] ? Date.parse(attrs["birthdate"]) : nil,
      country_code: attrs["address_country_code"],
      front_photo: attrs["front_photo"],
      back_photo: attrs["back_photo"],
      selfie_photo: attrs["selfie_photo"]
    )
  end

  def download_file(file_id)
    response = connection.get("/api/v1/files/#{file_id}")

    raise Persona::APIError, error_message(response) unless response.success?

    StringIO.new(response.body)
  end

  private

  def connection
    @connection ||= Faraday.new(url: BASE_URL) do |f|
      f.request :json
      f.response :json
      f.headers["Authorization"] = "Bearer #{@api_key}"
      f.headers["Persona-Version"] = "2025-12-08"
      f.headers["Key-Inflection"] = "snake"
      f.adapter Faraday.default_adapter
    end
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
