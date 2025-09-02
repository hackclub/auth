module PapersPleaseEngine
  class AadhaarScrutinizer < Base
    def run
      identity = verification.identity
      identity_first_name = identity.legal_first_name.presence || identity.first_name
      identity_last_name = identity.legal_last_name.presence || identity.last_name
      identity_date_of_birth = identity.birthday
      identity_aadhaar_number = identity.aadhaar_number

      aadhaar_record = verification.aadhaar_record

      issues = []

      split = aadhaar_record.name.split(" ")
      aadhaar_first_name = split.first
      aadhaar_last_name = split.last

      identity_name = "#{identity_first_name} #{identity_last_name}".downcase
      aadhaar_name = "#{aadhaar_first_name} #{aadhaar_last_name}".downcase

      if identity_name != aadhaar_name
        issues << if MiniLevenshtein.edit_distance(identity_name, aadhaar_name) > 4
          "Name doesn't seem to match"
        else
          "Name doesn't match exactly (this is probably fine)"
        end
      end

      if identity_date_of_birth != aadhaar_record.date_of_birth
        issues << "Date of birth doesn't match"
      end

      if identity_aadhaar_number[-4..] != aadhaar_record.doc_json.dig(:data, :aadhar_number)[-4..]
        issues << "entered Aadhaar number might not match?"
      end

      issues
    end
  end
end
