class Persona::MockAPIService
  MOCK_BEHAVIORS = {
    "behavior_threat_level" => "low",
    "bot_score" => 2,
    "request_spoof_attempts" => 0,
    "user_agent_spoof_attempts" => 0,
    "distraction_events" => 3,
    "hesitation_percentage" => 45.0,
    "shortcut_copies" => 0,
    "shortcut_pastes" => 0,
    "autofill_starts" => 0,
    "completion_time" => 148,
    "mobile_sdk_version_less_than_minimum_count" => 0,
    "api_version_less_than_minimum_count" => 0
  }.freeze

  MOCK_SESSION = {
    status: "active",
    browser_name: "Chrome",
    os_name: "Mac OS X",
    os_full_version: "10.15.7",
    device_type: "desktop",
    device_name: "Mac",
    is_proxy: false,
    is_tor: false,
    is_vpn: false,
    is_datacenter: false,
    threat_level: "low",
    country_code: "US",
    country_name: "United States",
    region_name: "California",
    latitude: 37.75,
    longitude: -122.42,
    ip_isp: "Comcast",
    ip_connection_type: "Cable/DSL"
  }.freeze

  def create_inquiry(template_id:, account_reference_id:, fields: {})
    mock_inquiry(
      id:            "inq_test_#{SecureRandom.hex(8)}",
      status:        "created",
      account_id:    "act_test_#{Digest::SHA256.hexdigest(account_reference_id)[0..11]}",
      session_token: "session_tok_#{SecureRandom.hex(16)}",
      verification_ids: [ { type: "verification/government-id", id: "ver_gov_test_#{SecureRandom.hex(8)}" } ],
      document_ids:     [ { type: "document/government-id", id: "doc_test_#{SecureRandom.hex(8)}" } ]
    )
  end

  def retrieve_inquiry(inquiry_id)
    mock_inquiry(
      id:     inquiry_id,
      status: "completed",
      verification_ids: [ { type: "verification/government-id", id: "ver_gov_#{inquiry_id.delete_prefix('inq_')}" } ],
      document_ids:     [ { type: "document/government-id", id: "doc_#{inquiry_id.delete_prefix('inq_')}" } ]
    )
  end

  def resume_inquiry(inquiry_id)
    mock_inquiry(id: inquiry_id, status: "pending", session_token: "session_tok_#{SecureRandom.hex(16)}")
  end

  def expire_inquiry(inquiry_id)
    mock_inquiry(id: inquiry_id, status: "expired")
  end

  def retrieve_document_photos(_document_id, type: "document/government-id")
    Persona::PhotoSet.new(
      document: [
        { filename: "front.jpg", url: "https://files.withpersona.com/front.jpg?access_token=mock", byte_size: 12345 },
        { filename: "back.jpg", url: "https://files.withpersona.com/back.jpg?access_token=mock", byte_size: 12345 }
      ],
      liveness: []
    )
  end

  def retrieve_verification_photos(_verification_id, type: "verification/government-id")
    case type
    when "verification/selfie"
      Persona::PhotoSet.new(
        document: [],
        liveness: [
          { url: "https://files.withpersona.com/center.jpg?access_token=mock", label: "selfie_center" },
          { url: "https://files.withpersona.com/left.jpg?access_token=mock", label: "selfie_left" },
          { url: "https://files.withpersona.com/right.jpg?access_token=mock", label: "selfie_right" }
        ]
      )
    else
      Persona::PhotoSet.empty
    end
  end

  MOCK_GOV_ID_RAW = {
    name_first: "HEIDI", name_middle: "J", name_last: "TRASHWORTH",
    birthdate: "2008-06-15", sex: "Female", country_code: "US",
    id_class: "dl", capture_method: "photo",
    document_number: "D1234567",
    issue_date: "2024-06-15", expiration_date: "2029-06-15",
    issuing_authority: "CA", issuing_subdivision: "California",
    address_street_1: "123 MOCK STREET", address_city: "SAN FRANCISCO",
    address_subdivision: "California", address_postal_code: "94109",
    entity_confidence_score: 0.98, entity_confidence_reasons: [],
    vehicle_class: "C", restrictions: "B",
    checks: [
      { "name" => "id_aamva_database_lookup", "status" => "passed", "reasons" => [], "requirement" => "not_required" },
      { "name" => "id_account_comparison", "status" => "passed", "reasons" => [], "requirement" => "not_required" },
      { "name" => "id_age_comparison", "status" => "passed", "reasons" => [], "requirement" => "not_required" },
      { "name" => "id_barcode_detection", "status" => "passed", "reasons" => [], "requirement" => "required" },
      { "name" => "id_entity_detection", "status" => "passed", "reasons" => [], "requirement" => "required" },
      { "name" => "id_expired_detection", "status" => "passed", "reasons" => [], "requirement" => "required" },
      { "name" => "id_extraction_detection", "status" => "passed", "reasons" => [], "requirement" => "required" }
    ]
  }.freeze

  def retrieve_government_id_verification(_verification_id)
    raw = MOCK_GOV_ID_RAW
    Persona::GovernmentIdVerification.new(
      id:                       "ver_test_#{SecureRandom.hex(8)}",
      status:                   "passed",
      name_first:               raw[:name_first],
      name_last:                raw[:name_last],
      birthdate:                Date.parse(raw[:birthdate]),
      country_code:             raw[:country_code],
      id_class:                 raw[:id_class],
      expiration_date:          Date.parse(raw[:expiration_date]),
      entity_confidence_score:  raw[:entity_confidence_score],
      checks:                   raw[:checks],
      front_photo:              { filename: "front.jpg", url: "https://files.withpersona.com/front.jpg?access_token=mock", byte_size: 12345 },
      back_photo:               { filename: "back.jpg", url: "https://files.withpersona.com/back.jpg?access_token=mock", byte_size: 12345 },
      selfie_photo:             nil,
      raw:                      raw
    )
  end

  def download_file(_url) = StringIO.new("mock image data for testing")

  def redact_account(_account_id) = true

  private

  def mock_inquiry(id:, status:, account_id: "act_test_mock", session_token: nil,
                   verification_ids: [], document_ids: [])
    active = %w[completed created].include?(status)
    Persona::Inquiry.new(
      id: id, status: status, account_id: account_id, session_token: session_token,
      verification_ids: verification_ids, document_ids: document_ids,
      behaviors: active ? MOCK_BEHAVIORS : {},
      sessions:  active ? [ MOCK_SESSION ] : [],
      raw:       { status: status, behaviors: active ? MOCK_BEHAVIORS : {} }
    )
  end
end
