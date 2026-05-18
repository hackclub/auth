FactoryBot.define do
  factory :program_collaborator do
    association :program
    association :identity
    invited_email { identity.primary_email }

    trait :accepted do
      status { "accepted" }
      accepted_at { Time.current }
    end
  end
end
