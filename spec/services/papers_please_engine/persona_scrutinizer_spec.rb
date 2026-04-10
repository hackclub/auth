require "rails_helper"

RSpec.describe PapersPleaseEngine::PersonaScrutinizer do
  let(:identity) do
    create(:identity,
      first_name: "Heidi", last_name: "Trashworth",
      legal_first_name: nil, legal_last_name: nil,
      birthday: Date.parse("2008-06-15"), country: :US)
  end

  let(:persona_record) do
    create(:identity_persona_record,
      identity: identity,
      name_first: "HEIDI",
      name_last: "TRASHWORTH",
      birthdate: Date.parse("2008-06-15"),
      country_code: "US",
      expiration_date: Date.parse("2029-06-15"),
      entity_confidence_score: 0.98,
      checks: [
        { "name" => "id_expired_detection", "status" => "passed", "reasons" => [], "requirement" => "required" },
        { "name" => "id_entity_detection", "status" => "passed", "reasons" => [], "requirement" => "required" }
      ]
    )
  end

  let(:verification) do
    create(:persona_verification, identity: identity, persona_record: persona_record, status: :pending)
  end

  subject { described_class.new(verification).run }

  context "when everything matches" do
    it "returns no issues" do
      expect(subject).to be_empty
    end
  end

  context "when name is slightly different" do
    before { persona_record.update!(name_first: "HEIDY") }

    it "flags minor mismatch" do
      expect(subject).to include(a_string_matching(/doesn't match exactly/i))
    end
  end

  context "when name is very different" do
    before { persona_record.update!(name_first: "ZEPHYR", name_last: "MOONBEAM") }

    it "flags strong mismatch" do
      expect(subject).to include(a_string_matching(/name doesn't seem to match/i))
    end
  end

  context "when DOB doesn't match" do
    before { persona_record.update!(birthdate: Date.parse("2007-01-01")) }

    it "flags DOB mismatch" do
      expect(subject).to include(a_string_matching(/date of birth doesn't match/i))
    end
  end

  context "when country doesn't match" do
    before { persona_record.update!(country_code: "CA") }

    it "flags country mismatch" do
      expect(subject).to include(a_string_matching(/country doesn't match/i))
    end
  end

  context "when document is expired" do
    before { persona_record.update!(expiration_date: 1.year.ago.to_date) }

    it "flags expiration" do
      expect(subject).to include(a_string_matching(/expired/i))
    end
  end

  context "when entity confidence is low" do
    before { persona_record.update!(entity_confidence_score: 0.5) }

    it "flags low confidence" do
      expect(subject).to include(a_string_matching(/low entity confidence/i))
    end
  end

  context "when a required Persona check failed" do
    before do
      persona_record.update!(checks: [
        { "name" => "id_expired_detection", "status" => "failed", "reasons" => ["document is expired"], "requirement" => "required" }
      ])
    end

    it "flags the failed check" do
      expect(subject).to include(a_string_matching(/persona check failed.*id expired detection/i))
    end

    it "includes the reason" do
      expect(subject).to include(a_string_matching(/document is expired/i))
    end
  end

  context "when a non-required check failed" do
    before do
      persona_record.update!(checks: [
        { "name" => "id_aamva_database_lookup", "status" => "failed", "reasons" => [], "requirement" => "not_required" }
      ])
    end

    it "does not flag non-required failures" do
      expect(subject).to be_empty
    end
  end

  context "when legal name is set and matches" do
    before do
      identity.update!(legal_first_name: "Heidi-Marie", legal_last_name: "Trashworth")
      persona_record.update!(name_first: "HEIDI-MARIE")
    end

    it "compares against legal name" do
      expect(subject).to be_empty
    end
  end

  context "when persona_record is nil" do
    let(:verification) do
      create(:persona_verification, identity: identity, persona_record: nil)
    end

    it "returns no issues" do
      expect(subject).to be_empty
    end
  end
end
