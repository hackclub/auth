FactoryBot.define do
  factory :identity_document, class: "Identity::Document" do
    association :identity
    document_type { :government_id }

    after(:build) do |doc|
      doc.files.attach(
        io: StringIO.new("fake image data"),
        filename: "id_front.jpg",
        content_type: "image/jpeg"
      )
    end

    trait :transcript do
      document_type { :transcript }

      after(:build) do |doc|
        doc.files.attach(
          io: StringIO.new("fake transcript"),
          filename: "transcript.pdf",
          content_type: "image/jpeg"
        )
      end
    end
  end

  factory :identity_persona_record, class: "Identity::PersonaRecord" do
    association :identity
    inquiry_id { "inq_#{SecureRandom.hex(12)}" }
    raw_json_response { { inquiry: { id: "inq_test", status: "approved" }, government_id_verification: {} }.to_json }
    name_first { "Heidi" }
    name_last { "Trashworth" }
    birthdate { Date.parse("2005-06-15") }
    country_code { "US" }
    persona_status { "approved" }
    id_class { "dl" }
    expiration_date { 3.years.from_now.to_date }
    entity_confidence_score { 0.98 }
    checks { [] }
  end

  factory :document_verification, class: "Verification::DocumentVerification" do
    association :identity
    association :identity_document
    status { :pending }
  end

  factory :aadhaar_verification, class: "Verification::AadhaarVerification" do
    association :identity
    status { :draft }
    aadhaar_hc_transaction_id { "HC!#{SecureRandom.uuid}" }
  end

  factory :vouch_verification, class: "Verification::VouchVerification" do
    association :identity
    status { :approved }

    after(:build) do |vouch|
      vouch.evidence.attach(
        io: StringIO.new("vouch evidence"),
        filename: "evidence.pdf",
        content_type: "application/pdf"
      )
    end
  end

  factory :persona_verification, class: "Verification::PersonaVerification" do
    association :identity
    status { :draft }
    persona_inquiry_id { "inq_#{SecureRandom.hex(12)}" }

    trait :with_inquiry do
      persona_session_token { "session_#{SecureRandom.hex(16)}" }
    end

    trait :pending do
      status { :pending }
      association :persona_record, factory: :identity_persona_record
      association :identity_document
    end

    trait :approved do
      status { :approved }
      association :persona_record, factory: :identity_persona_record
      association :identity_document
    end

    trait :rejected do
      status { :rejected }
      rejection_reason { "info_mismatch" }
      association :persona_record, factory: :identity_persona_record
    end

    trait :fatal_rejection do
      status { :rejected }
      fatal { true }
      rejection_reason { "duplicate" }
      association :persona_record, factory: :identity_persona_record
    end
  end
end
