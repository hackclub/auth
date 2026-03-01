FactoryBot.define do
  factory :program_collaborator do
    association :program
    association :identity
  end
end
