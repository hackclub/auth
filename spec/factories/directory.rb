FactoryBot.define do
  factory :directory_person, class: 'Directory::Person' do
    identity { association :identity }
    created_by { identity }
  end

  factory :directory_group, class: 'Directory::Group' do
    sequence(:slug) { |n| "group-#{n}" }
    sequence(:name) { |n| "Group #{n}" }
  end

  factory :directory_entitlement, class: 'Directory::Entitlement' do
    sequence(:slug) { |n| "entitlement-#{n}" }
    sequence(:name) { |n| "Entitlement #{n}" }
  end

  factory :directory_membership, class: 'Directory::Membership' do
    collection { association :directory_group }

    trait :person do
      member_person { association :directory_person }
    end

    trait :group do
      member_group { association :directory_group }
    end
  end

  factory :directory_grant, class: 'Directory::Grant' do
    grantee_group { association :directory_group }
    target_collection { association :directory_group }
    permission { 'view' }
  end
end
