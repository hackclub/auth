FactoryBot.define do
  factory :verification_case do
    association :identity
    status { :requested }

    trait :link_sent do
      status { :link_sent }
      document_class { "government_id" }
      access_token { SecureRandom.urlsafe_base64(32) }
      access_token_expires_at { 7.days.from_now }
    end

    trait :alternative do
      document_class { "alternative" }
      alternative_reason { "no_government_id" }
    end

    trait :skip_persona do
      skip_persona { true }
    end

    trait :docs_submitted do
      link_sent
      status { :docs_submitted }
      attested { true }
      biometric_consent { true }
    end

    trait :call_scheduled do
      docs_submitted
      status { :call_scheduled }
      booking_uid { "bkng_#{SecureRandom.hex(6)}" }
      call_starts_at { 2.days.from_now }
      recording_consent_acknowledged { true }
    end

    trait :call_held do
      call_scheduled
      status { :call_held }
    end
  end

  factory :verification_case_document, class: "VerificationCase::Document" do
    association :verification_case
    document_kind { "primary_doc" }
    source { "direct_upload" }

    after(:build) do |doc|
      doc.file.attach(
        io: StringIO.new("fake document"),
        filename: "document.pdf",
        content_type: "application/pdf"
      )
    end

    trait :recording do
      document_kind { "call_recording" }
      source { "call_recording" }
    end

    trait :expired_retention do
      retention_delete_at { 1.day.ago }
    end
  end

  factory :manual_verification_call, class: "Verification::ManualVerificationCall" do
    association :identity
    association :reviewer, factory: :backend_user
    status { :pending }
    checklist do
      {
        "doc_matches_live_face" => true,
        "doc_matches_selfie" => true,
        "name_dob_consistent" => true,
        "signals_clean" => true,
        "doc_unaltered" => true,
        "confidence" => "high",
        "notes" => "all clear on the call"
      }
    end
  end
end
