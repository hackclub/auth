module PapersPleaseEngine
  class PersonaScrutinizer < Base
    CONFIDENCE_THRESHOLD = 0.85

    ID_CLASS_LABELS = {
      "dl" => "driver's license",
      "pp" => "passport",
      "id" => "national ID",
      "rp" => "residence permit",
      "vi" => "visa"
    }.freeze

    def run
      record = verification.persona_record
      return [] unless record

      identity = verification.identity
      issues = []

      # --- Name comparison ---
      identity_first = (identity.legal_first_name.presence || identity.first_name).downcase
      identity_last = (identity.legal_last_name.presence || identity.last_name).downcase
      persona_first = record.name_first&.downcase
      persona_last = record.name_last&.downcase

      if persona_first && persona_last
        identity_name = "#{identity_first} #{identity_last}"
        persona_name = "#{persona_first} #{persona_last}"

        if identity_name != persona_name
          distance = MiniLevenshtein.edit_distance(identity_name, persona_name)
          issues << if distance > 4
            "Name doesn't seem to match (profile: #{identity_first} #{identity_last}, ID: #{persona_first} #{persona_last})"
          else
            "Name doesn't match exactly — probably fine (profile: #{identity_first} #{identity_last}, ID: #{persona_first} #{persona_last})"
          end
        end
      end

      # --- DOB comparison ---
      if identity.birthday && record.birthdate && identity.birthday != record.birthdate
        issues << "Date of birth doesn't match (profile: #{identity.birthday}, ID: #{record.birthdate})"
      end

      # --- Country comparison ---
      if record.country_code.present? && identity.country.present?
        # identity.country is an enum string like "US", record.country_code is ISO alpha-2
        identity_cc = identity.country.upcase
        persona_cc = record.country_code.upcase
        if identity_cc != persona_cc
          issues << "Country doesn't match (profile: #{identity_cc}, ID: #{persona_cc})"
        end
      end

      # --- Document expiration ---
      if record.expiration_date && record.expiration_date < Date.current
        issues << "Document expired on #{record.expiration_date}"
      end

      # --- Entity confidence ---
      if record.entity_confidence_score && record.entity_confidence_score < CONFIDENCE_THRESHOLD
        issues << "Low entity confidence score: #{(record.entity_confidence_score * 100).round(1)}%"
      end

      # --- Persona's own checks ---
      failed_checks = (record.checks || []).select { |c| c["status"] == "failed" && c["requirement"] == "required" }
      failed_checks.each do |check|
        name = check["name"].to_s.tr("_", " ")
        reasons = check["reasons"]&.compact&.join(", ")
        msg = "Persona check failed: #{name}"
        msg += " (#{reasons})" if reasons.present?
        issues << msg
      end

      issues
    end
  end
end
