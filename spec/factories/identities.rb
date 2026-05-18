FactoryBot.define do
  factory :identity do
    first_name { "Heidi" }
    last_name { "Trashworth" }
    sequence(:primary_email) { |n| "heidi#{n}@hackclub.com" }
    birthday { Date.parse("2005-06-15") }
    country { "US" }
    phone_number { "+18028675309" }
    sequence(:slack_id) { |n| "U#{n.to_s.rjust(8, '0')}" }
    ysws_eligible { true }
    legal_first_name { "Hakkuun" }
    legal_last_name { "[WOULDN'T YOU LIKE TO KNOW]" }

    trait :with_address do
      after(:create) do |identity|
        address = create(:address, identity: identity)
        identity.update(primary_address: address)
      end
    end

    trait :can_hq_officialize do
      can_hq_officialize { true }
    end

    trait :developer do
      developer_mode { true }
    end
  end
end
