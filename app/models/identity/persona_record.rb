class Identity::PersonaRecord < ApplicationRecord
  acts_as_paranoid

  belongs_to :identity

  has_one :verification, class_name: "Verification::PersonaVerification", foreign_key: "persona_record_id", dependent: :destroy

  encrypts :raw_json_response

  has_many :break_glass_records, as: :break_glassable, dependent: :destroy

  validates :inquiry_id, presence: true, uniqueness: true
  validates :raw_json_response, presence: true

  ID_CLASS_LABELS = {
    "dl" => "driver's license",
    "pp" => "passport",
    "id" => "national ID",
    "rp" => "residence permit",
    "vi" => "visa"
  }.freeze

  def id_class_label = ID_CLASS_LABELS[id_class] || id_class

  # -- hydration from encrypted raw response ---------------------------------

  def doc_json
    @doc_json ||= JSON.parse(raw_json_response.strip, symbolize_names: true)
  end

  def gov_id_data  = doc_json[:government_id_verification] || {}
  def session_data = doc_json[:sessions] || []

  def full_name
    [name_first, gov_id_data[:name_middle], name_last, gov_id_data[:name_suffix]]
      .compact_blank.join(" ")
  end

  def document_number     = gov_id_data[:document_number]
  def issue_date          = gov_id_data[:issue_date]&.then { |d| Date.parse(d) rescue d }
  def issuing_authority   = gov_id_data[:issuing_authority]
  def issuing_subdivision = gov_id_data[:issuing_subdivision]
  def sex                 = gov_id_data[:sex]
  def birthplace          = gov_id_data[:birthplace]
  def nationality         = gov_id_data[:nationality]
  def capture_method      = gov_id_data[:capture_method]

  def address_lines
    street = [gov_id_data[:address_street_1], gov_id_data[:address_street_2]].compact_blank
    city_state = [gov_id_data[:address_city], gov_id_data[:address_subdivision]].compact_blank.join(", ")
    city_state_zip = [city_state, gov_id_data[:address_postal_code]].compact_blank.join(" ")
    lines = []
    lines << street.join(", ") if street.any?
    lines << city_state_zip if city_state_zip.present?
    lines
  end

  # -- network signals (from inquiry sessions) --------------------------------

  def primary_session = session_data.first || {}

  def device_summary
    s = primary_session
    parts = [s[:browser_name], s[:os_name], s[:device_type]].compact_blank
    parts.any? ? parts.join(", ") : nil
  end

  NETWORK_FLAGS = %w[is_tor is_proxy is_vpn is_datacenter].freeze

  def network_flags
    s = primary_session
    NETWORK_FLAGS.filter_map { |f| f.delete_prefix("is_").upcase if s[f.to_sym] }
  end

  def ip_location
    s = primary_session
    [s[:region_name], s[:country_name]].compact_blank.join(", ").presence
  end

  def ip_isp = primary_session[:ip_isp]
  def session_threat_level = primary_session[:threat_level]

  # -- behavioral signals (JSONB column, queryable) ---------------------------

  def behavior_threat_level = behaviors&.dig("behavior_threat_level")
  def bot_score = behaviors&.dig("bot_score")

  BEHAVIOR_DISPLAY = [
    { key: "behavior_threat_level", label: "threat level" },
    { key: "bot_score",             label: "bot score" },
    { key: "completion_time",       label: "completion time" },
    { key: "distraction_events",    label: "distractions" },
    { key: "hesitation_percentage", label: "hesitation" },
    { key: "hesitation_count",      label: "hesitation count" },
    { key: "hesitation_time",       label: "hesitation time" },
    { key: "hesitation_baseline",   label: "hesitation baseline" },
    { key: "shortcut_copies",       label: "copies" },
    { key: "shortcut_pastes",       label: "pastes" },
    { key: "autofill_starts",       label: "autofills" },
    { key: "autofill_cancels",      label: "autofill cancels" },
    { key: "request_spoof_attempts",    label: "request spoofs" },
    { key: "user_agent_spoof_attempts", label: "UA spoofs" },
    { key: "devtools_open",         label: "devtools open" },
    { key: "debugger_attached",     label: "debugger attached" },
    { key: "mobile_sdk_version_less_than_minimum_count", label: "restricted SDK reqs" },
    { key: "api_version_less_than_minimum_count",        label: "restricted API reqs" }
  ].freeze

  def formatted_behaviors
    return [] if behaviors.blank?
    BEHAVIOR_DISPLAY.filter_map do |spec|
      value = behaviors[spec[:key]]
      next if value.nil?
      { label: spec[:label], value: format_behavior(spec[:key], value), key: spec[:key] }
    end
  end

  private

  def format_behavior(key, value)
    case key
    when "completion_time", "hesitation_time", "hesitation_baseline"
      format_duration(value)
    when "hesitation_percentage"
      "#{value.is_a?(Numeric) ? value.round(1) : value}%"
    else
      value.to_s
    end
  end

  def format_duration(seconds)
    return "—" unless seconds
    m, s = seconds.to_f.divmod(60)
    m > 0 ? "#{m.to_i}m #{s.round}s" : "#{s.round}s"
  end
end
