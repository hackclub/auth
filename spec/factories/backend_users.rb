FactoryBot.define do
  factory :backend_user, class: "Backend::User" do
    sequence(:username) { |n| "admin#{n}" }
    active { true }
    super_admin { false }
    program_manager { false }
    manual_document_verifier { false }
    human_endorser { false }
    all_fields_access { false }
    can_break_glass { false }
    association :identity

    trait :super_admin do
      super_admin { true }
    end

    trait :program_manager do
      program_manager { true }
    end

    trait :mdv do
      manual_document_verifier { true }
    end
  end
end
